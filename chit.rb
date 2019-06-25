#!/usr/bin/env ruby

# Chit － したらば掲示板をチャット風に使う対話的インターフェース

require 'readline'
require_relative 'bbs_reader'
require_relative 'post-test'
require_relative 'res_format'

module Chit
  module_function

  # スレッド指定文字列：
  #    [カテゴリー]/[掲示板番号]/[スレッドパターン]:[オプション]
  #
  # 例えば game/1234/ABC*:postable,oldest で game/1234 掲示板の スレッド
  # タイトルが ABC で始まるスレッドの内、スレッドストップになっておらず
  # 一番古くから存在するものを選択する。
  #
  # [スレッドパターン]はワイルドカード ? * を含むことのできるスレッドタイトルか、
  # あるいは、スレッド番号（スレッドが立てられた Unix Time である整数）。
  #
  # [オプション]は、以下の単語をコンマ区切りで並べたもの。
  # * oldest (一番古くに立てられたスレッドを選択)
  # * postable (スレッドストップになっていないスレッドを選択)

  # スレッド指定文字列 specstr に合致する Thread のリストを返す。
  def search_threads(specstr)
    spec  = parse_thread_spec(specstr)
    board = Bbs::Shitaraba::Board.send(:new, spec[:category], spec[:board_num])
    ts    = board.threads.select!{ |t| t.title =~ spec[:thread_regexp] }

    if spec[:options].delete(:postable)
      ts.select! { |t| t.last < 1000 }
    end

    if spec[:options].delete(:oldest)
      ts = [ts.min_by(&:id)]
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
    options = []
    if str =~ /(.*):(.*)/
      str = $1
      options = $2.split(',').map(&:to_sym)
    end
    words = str.split('/')
    fail "invalid thread spec #{str.inspect}" unless words.size==3
    fail "invalid board id #{words[1].inspect}" unless words[1] =~ /\A\d+\z/
    {
      category: words[0],
      board_num: words[1],
      thread_pattern: words[2],
      thread_regexp: glob_to_regexp(words[2]),
      options: options
    }
  end

  def main
    unless ARGV.size == 1
      STDERR.puts "Usage: chit THREAD_SPEC"
      exit 1
    end

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
      [first_thread, first_thread.last+1]
    end

    # 以下のループはユーザーから行を受け取り、スレッドに投稿する。投稿し
    # たあとは新レスの取得と表示を行う（これにはユーザーが投稿した内容が
    # 含まれるはずである）。ユーザーがただEnterを押した場合は、新レスの
    # 取得・表示のみを行う。スレッドストップにあたっては、スレッドの検索
    # をやりなおし、該当スレッドがあればそれを投稿先として選択する。
    t, start_no = move_to_new_thread.()
    while true
      if start_no > 1000
        STDERR.puts "Thread full"
        t, start_no = move_to_new_thread.()
      end

      body = Readline.readline("#{t.title}> ", true)
      break if body.nil? # EOF

      # 投稿。
      unless body.empty?
        begin
          post_message(t.board.category,
                       t.board.board_num,
                       t.id,
                       name, mail, body)
        rescue RateLimitException => e
          sleep e.cooldown
          retry
        end
      end

      # 読み込み。
      begin
        t.posts(start_no .. Float::INFINITY).each do |post|
          puts render_post_chat(post)
          start_no += 1
        end
      rescue => e
        # レス取得エラー
        STDERR.print "Error: "
        STDERR.puts e.message
      end
    end
  end # main

end # module Chit

if __FILE__ == $0
  Chit.main
end
