require 'uri'
require 'net/http'

def to_euc(utf8)
  # TODO: EUCで表現できないコードはエスケープしたい。
  utf8.encode('EUC-JP')
end

def euc_to_utf8(str)
  str.force_encoding('EUC-JP').encode('UTF-8')
end

class RateLimitException < RuntimeError
  attr_reader :cooldown, :message
  def initialize(message, cooldown)
    @message = message
    @cooldown = cooldown
  end
end

class ThreadStopError < RuntimeError
end

def post_message(cat, board, thread, name, mail, body)
  uri = URI("https://jbbs.shitaraba.net/bbs/write.cgi/#{cat}/#{board}/#{thread}/")
  referer = "https://jbbs.shitaraba.net/bbs/read.cgi/#{cat}/#{board}/#{thread}/"

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    req = Net::HTTP::Post.new(uri)
    req['User-Agent'] = "Chit/0.0.1"
    req['Referer'] = referer
    req.set_form_data(
      "BBS" => board.to_s,
      "KEY" => thread.to_s,
      "DIR" => cat,
      "NAME"=> to_euc(name),
      "MAIL" => to_euc(mail),
      "MESSAGE" => to_euc(body))

    res = http.request(req)

    case res
    when Net::HTTPOK
      res_body = euc_to_utf8(res.body)
      unless res_body =~ /書きこみました/
        STDERR.puts "Warning: サーバーのOK応答に成功メッセージが確認できませんでした。"
      end
      return true
    else
      res_body = euc_to_utf8(res.body)
      if res_body =~ /多重書き込みです。あと (\d+) 秒お待ちください/
        raise RateLimitException.new("サーバー応答: #{$&}", $1.to_i)
      elsif res_body =~ /スレッドストップです/
        raise ThreadStopError.new
      else
        STDERR.puts res.inspect
        STDERR.puts res_body
        raise "投稿失敗"
      end
    end
  end
end
