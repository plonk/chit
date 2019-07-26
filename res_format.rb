require 'colorize'
require 'cgi'

def render_name(name, email)
  if email.empty?
    name
  else
    [name.bold, '(', email.light_black, ')'].join()
  end
end

def render_resno(no)
  no.to_s
end

def render_dateid(date, id)
  if id.nil?
    date
  else
    [date, id].join(' ID:')
  end
end

def render_date2time(date)
  date.match(/\d{2}:\d{2}:\d{2}/)
end

def indent(n, text)
  text.each_line.map { |line| " "*n + line }.join
end

def render_body(body, inde=true)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, "\n"))
  (inde ? indent(4, unescaped) : unescaped) + "\n"
end

def render_body_inline(body)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, ""))
end

# 複数行 所謂2chスタイル
def render_post(post)
  "#{render_resno(post.no).cyan.bold}：#{render_name(post.name, post.mail)}：#{render_dateid(post.date, post.id)}\n" \
  "#{render_body post.body}"
end

def render_post_chat_multiline(post)
  "#{render_resno(post.no).cyan.bold} : #{render_body(post.body, false)}"
end

# 単行 インラインチャットスタイル
def render_post_chat(post)
  "#{render_resno(post.no).cyan.bold} : #{render_body_inline post.body}"
end

# 単行 インラインチャットスタイル＋時刻
def render_post_chat_time(post)
  "#{render_resno(post.no).cyan.bold} <#{render_date2time post.date}> : #{render_body_inline post.body}"
end


