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
  # [オプション]は、以下の単語をコンマ区切りで並べたもの。
  # * oldest (一番古くに立てられたスレッドを選択)
  # * postable (スレッドストップになっていないスレッドを選択)
  # * multilines (番号:名前:日付:ID 本文と複数行で表示)

  def create_board(spec)
    case spec[:protocol]
    when :shitaraba
      Bbs.create_board("http://#{spec[:host]}/#{spec[:board]}/")
    when :nichan
      Bbs.create_board("http://#{spec[:host]}/#{spec[:board]}/")
    end
  end

  # スレッド指定文字列 specstr に合致する Thread のリストを返す。
  def search_threads(specstr)
    spec  = parse_thread_spec(specstr)
    board = create_board(spec)
    ts    = board.threads.select{ |t| t.title =~ spec[:thread_regexp] }

    if spec[:options].delete(:postable)
      ts.select! { |t| t.last < 1000 }
    end

    if spec[:options].delete(:oldest)
      ts = [ts.min_by(&:id)]
    end

    if spec[:options].delete(:multilines)
      Bbs.set_multilines(true)
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

    host, board, thread_pattern = str.split('/',3)
    {
      protocol: :shitaraba,
      host: host,
      board: board,
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
    {
      protocol: :nichan,
      host: host.empty? ? "jbbs.shitaraba.net" : host,
      board: words[1..2].join('/'),
      thread_pattern: words[3],
      thread_regexp: glob_to_regexp(words[3]),
      options: options
    }
  end

  HISTORY_FILE = File.join(ENV['HOME'], ".config/chit/history")

  def main
    unless ARGV.size == 1
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
        rl_set_prompt("#{t.tile}> ")
      end

      # 読み込み。
      begin
        t.posts(start_no .. Float::INFINITY).each do |post|
          puts Bbs.get_multilines ? render_post(post) : render_post_chat(post)
          start_no += 1
        end
      rescue => e
        # レス取得エラー
        STDERR.print "Error: "
        STDERR.puts e.message
      end

      body = Readline.readline("#{t.title}> ", true)
      break if body.nil? # EOF

      # 投稿。
      unless body.empty?
        begin
          posts = t.posts(start_no .. Float::INFINITY)
          if posts.any?
            rl_clear_visible_line
            ReadlineFFI::CFFI.fflush(nil)

            posts.each do |post|
              puts render_post_chat(post)
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
