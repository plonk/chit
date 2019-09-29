#!/usr/bin/env ruby

# Chit － したらば掲示板をチャット風に使う対話的インターフェース

require 'fileutils'
require_relative 'bbs_reader'
require_relative 'post-test'
require_relative 'res_format'
require_relative 'readline-ffi'

module Chit
  extend ReadlineFFI
  module_function
  @multilines = false
  @inlinetime = false
  @threadmode = false
  @last10 = false
  @proxy = ""
  attr_reader :multilines, :inlinetime, :threadmode, :last10, :proxy
  
  # スレッド指定文字列：
  #    [プロトコル]://[ホスト]/[掲示板]/[スレッドパターン]:[オプション]
  #
  # 例えば shitaraba:///game/1234/ABC*:postable,oldest で game/1234 掲
  # 示板の スレッドタイトルが ABC で始まるスレッドの内、スレッドストッ
  # プになっておらず一番古くから存在するものを選択する。
  #
  # [スレッドパターン]はワイルドカード ? * を含むことのできるスレッド
  # タイトルか、あるいは、スレッド番号（スレッドが立てられた Unix Time
  # である整数）。
  #
  # [オプション]は、以下の単語をコンマ区切りで並べたもの。[]は省略オプション
  # * oldest     [O] (一番古くに立てられたスレッドを選択)
  # * postable   [P] (スレッドストップになっていないスレッドを選択)
  # * showtime   [S] (番号<時刻>: 本文 と時刻を追加して表示)
  # * multilines [M] (改行を改行して複数行で表示、showtimeと同時だと所謂2chスタイル)
  # * thread     [T] (強制スレッドモード)
  # * last10     [L] (最新レスから10だけ表示して開始)

  def create_board(spec)
    case spec[:protocol]
    when :shitaraba
      Bbs.create_board("http://#{spec[:host]}/#{spec[:board]}/")
    when :nichan
      Bbs.create_board("http://#{spec[:host]}#{spec[:path]}/#{spec[:board]}/")
    end
  end

  # スレッド指定文字列 specstr に合致する Thread のリストを返す。
  def search_threads(specstr)
    spec  = parse_thread_spec(specstr)
    # 前に書かないといけないのやだなんとかしたい
    if spec[:options].delete(:thread) || spec[:options].delete(:T)
      @threadmode  = true
    end

    board = create_board(spec)
    if spec[:thread_num] == 0 || !@threadmode
      ts = board.threads.select{ |t| t.title =~ spec[:thread_regexp] }
    else
      ts = [board.thread(spec[:thread_num])]
    end

    if spec[:options].delete(:postable) || spec[:options].delete(:P)
      ts.select! { |t| t.last < 1000 }
    end

    if spec[:options].delete(:oldest) || spec[:options].delete(:O)
      ts = [ts.min_by(&:id)]
    end

    if spec[:options].delete(:multilines) || spec[:options].delete(:M)
      @multilines = true
    end
    
    if spec[:options].delete(:showtime) || spec[:options].delete(:S)
      @inlinetime = true
    end

    if spec[:options].delete(:last10) || spec[:options].delete(:L)
      @last10  = true
    end

    return ts
  end

  # 文字列のリスト arr から glob パターン pat に合致するものを返す。
  def glob(pat, arr)
    arr.grep(glob_to_regexp(pat))
  end

  # glob パターンを正規表現に変換する。
  def glob_to_regexp(pat)
    re = '\A'
    until pat.empty?
      case pat
      when /\A\?/
        re += "."
      when /\A\*/
        re += ".*"
      when /\A./
        re += Regexp.escape($&)
      else fail
      end
      pat = $'
    end
    re += '\z'
    Regexp.new(re)
  end

  # スレッド指定文字列を解釈してキーワードをキーとする Hash を返す。Hash
  # のキーは、:category (板カテゴリ), :board_num (カテゴリ内での板番号),
  # :thread_pattern (板内でスレッドを選択するパターン文字列),
  # :thread_regexp (上記パターン文字列と同等な Regexp), :options (キーワー
  # ド :postable, :oldest の０個以上を含むリスト)。
  def parse_thread_spec(str)
    if str =~ /^shitaraba:\/\//
      parse_shitaraba_thread_spec($')
    elsif str =~ /^nichan:\/\//
      parse_nichan_thread_spec($')
    else
      fail 'invalid spec'
    end
  end

  def parse_nichan_thread_spec(str)
    options = []
    if str =~ /(.*):(.*)/
      str = $1
      options = $2.split(',').map(&:to_sym)
    end

    words = str.split('/')
    words.delete('test') unless words.delete('read.cgi').nil?
    #host, board, thread_pattern = words
    thread_pattern, board, *host = words.reverse
    host, *path = host.reverse
    path = [path].join("/")
    thread_num = thread_pattern =~ /^(\d+)$/ ? $1 : 0
    {
      protocol: :nichan,
      host: host,
      path: path.empty? ? "": "/" + path,
      board: board,
      thread_num: thread_num.to_i,
      thread_pattern: thread_pattern,
      thread_regexp: glob_to_regexp(thread_pattern),
      options: options,
    }
  end

  def parse_shitaraba_thread_spec(str)
    options = []
    if str =~ /(.*):(.*)/
      str = $1
      options = $2.split(',').map(&:to_sym)
    end

    words = str.split('/')
    host, = words
    fail "invalid thread spec #{str.inspect}" unless words.size==4
    fail "invalid board id #{words[1].inspect}" unless words[2] =~ /\A\d+\z/
    thread_num = words[3] =~ /^(\d+)$/ ? $1 : 0
    {
      protocol: :shitaraba,
      host: host.empty? ? "jbbs.shitaraba.net" : host,
      board: words[1..2].join('/'),
      thread_num: thread_num.to_i,
      thread_pattern: words[3],
      thread_regexp: glob_to_regexp(words[3]),
      options: options,
    }
  end

  HISTORY_FILE = File.join(ENV['HOME'], ".config/chit/history")

  def main
    unless ARGV.size <= 2
      STDERR.puts "Usage: chit THREAD_SPEC"
      exit 1
    end

    read_history(HISTORY_FILE)

    name = ""
    mail = "sage"

    # コマンドライン引数で指定されたスレッドを検索する。Thread オブジェ
    # クトと次に読み込むべきレスの番号を返す。
    move_to_new_thread = proc do
      first_thread, = search_threads(ARGV[0])
      unless first_thread
        STDERR.puts "No such thread"
        exit 1
      end
      [first_thread, 1]
    end

    last_fetch = nil
    t = nil
    running = true
    line_handler = proc do |body|
      body&.force_encoding("UTF-8")
      if body.nil?
        ReadlineFFI.rl_callback_handler_remove
        running = false
      else
        if body.empty?
          last_fetch = nil # すぐにレスを読み込みたい。
        else
          add_history(body)
          begin
            post_message(t.board,
                         t.id,
                         name, mail, body)
            last_fetch = nil # すぐに自分のレスを読み込みたい。
          rescue RateLimitException => e
            sleep e.cooldown
            retry
          end
        end
      end
    end

    # 以下のループはユーザーから行を受け取り、スレッドに投稿する。投稿し
    # たあとは新レスの取得と表示を行う（これにはユーザーが投稿した内容が
    # 含まれるはずである）。ユーザーがただEnterを押した場合は、新レスの
    # 取得・表示のみを行う。スレッドストップにあたっては、スレッドの検索
    # をやりなおし、該当スレッドがあればそれを投稿先として選択する。
    t, start_no = move_to_new_thread.()

    # ラインハンドラーをインストール。プロンプトが表示される。
    rl_callback_handler_install("#{t.title}> ", line_handler)

    while running
      if start_no > 1000
        STDERR.puts "Thread full"
        t, start_no = move_to_new_thread.()
        rl_set_prompt("#{t.title}> ")
      end

      # 読み込み。
      if last_fetch.nil? || Time.now - last_fetch >= 7.0
        begin
          posts = t.posts(start_no .. Float::INFINITY)
          if posts.any?
            rl_clear_visible_line
            ReadlineFFI::CFFI.fflush(nil)
            
            posts.each do |post|
              #puts render_post_chat(post)
              #ここすごく冗長なので直したい
              #case ((@multilines ? 0b01 : 0b00) | (@inlinetime ? 0b10 : 0b00))
              puts(
                if @multilines
                  @inlinetime ? render_post(post) : render_post_chat_multiline(post)
                else
                  @inlinetime ? render_post_chat_time(post) : render_post_chat(post)
                end
              ) unless @last10 && start_no < t.last - 10
              
              start_no += 1
            end

            rl_forced_update_display
          end
          last_fetch = Time.now
        rescue => e
          # レス取得エラー
          STDERR.print "Error: "
          STDERR.puts e.message
        end
      end

      r = IO.select([STDIN], [], [], 7.0)
      if r
        rl_callback_read_char
      end
    end
  ensure
    FileUtils.mkdir_p(File.dirname(HISTORY_FILE))
    if (errno = write_history(HISTORY_FILE)) != 0
      STDERR.puts("write_histry: #{ReadlineFFI::CFFI.strerror(errno)}")
    end
    rl_deprep_terminal
  end # main

end # module Chit

if __FILE__ == $0
  Chit.main
end
