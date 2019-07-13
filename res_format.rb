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

def indent(n, text)
  text.each_line.map { |line| " "*n + line }.join
end

def render_body(body)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, "\n"))
  indent(4, unescaped) + "\n"
end

def render_post(post)
  "#{render_resno(post.no).cyan.bold}：#{render_name(post.name, post.mail)}：#{render_dateid(post.date, post.id)}\n" \
  "#{render_body post.body}"
end

def render_body_inline(body)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, ""))
end

def render_post_chat(post)
  "#{render_resno(post.no).cyan.bold} : #{render_body_inline post.body}"
end
