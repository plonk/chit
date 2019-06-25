require 'colorize'
require 'cgi'

def render_name(name, email)
  if email.empty?
    name
  else
    name
  end
end

def render_resno(no)
  no.to_s
end

def indent(n, text)
  text.each_line.map { |line| " "*n + line }.join
end

def render_body(body)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, "\n"))
  indent(4, unescaped) + "\n"
end

def render_post(post)
  "#{render_resno post.no}：#{render_name post.name, post.mail}：#{post.date}\n" \
  "#{render_body post.body}"
end

def render_body_inline(body)
  unescaped = CGI.unescapeHTML(body.gsub(/<br>/i, ""))
end

def render_post_chat(post)
  "#{render_resno(post.no).cyan.bold} : #{render_body_inline post.body}"
end
