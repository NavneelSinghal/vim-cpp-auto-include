if exists("g:loaded_cpp_auto_include")
    finish
endif

if !has("ruby")
    echohl ErrorMsg
    echon "Sorry, cpp_auto_include requires ruby support."
    finish
endif

let g:loaded_cpp_auto_include = "true"

autocmd BufWritePre /tmp/**.cc :ruby CppAutoInclude::process
autocmd BufWritePre /tmp/**.cpp :ruby CppAutoInclude::process

ruby << EOF
module VIM
  # make VIM's builtin VIM ruby module a little easier to use
  class << self
    # ['line1', 'line2' ... ]
    # [['line1', 1], ['line2', 2] ... ] if with_numbers
    def lines(with_numbers = false)
      lines = $curbuf.length.times.map { |i| $curbuf[i + 1] }
      with_numbers ? lines.zip(1..$curbuf.length) : lines
    end

    # if the line after #i != content,
    # append content after line #i
    def append(i, content)
      return false if ($curbuf.length >= i+1 && $curbuf[i+1] == content) 
      cursor = $curwin.cursor
      $curbuf.append(i, content)
      $curwin.cursor = [cursor.first+1,cursor.last] if cursor.first >= i
    end

    # remove line #i while (line #i = content)
    # or remove line #i once if content is nil
    # or find and remove line = content if i is nil
    def remove(i, content = nil)
      i ||= $curbuf.length.times { |i| break i + 1 if $curbuf[i + 1] == content }
      return if i.nil?

      content ||= $curbuf[i]

      while $curbuf[i] == content && i <= $curbuf.length
        cursor = $curwin.cursor
        $curbuf.delete(i)
        $curwin.cursor = [[1,cursor.first-1].max,cursor.last] if cursor.first >= i
      end
    end
  end
end


module CppAutoInclude
  HEADER_STD_KEYWORDS = [
    ['cstdio',   false , ['scanf', 'FILE', 'puts', 'printf']],
    ['cassert',  false , ['assert']],
    ['cstring',  false , ['memset', 'strlen', 'strerror', /strn?cmp/, 'strcat', 'memcmp']],
    ['cstdlib',  false , ['abs','EXIT_','NULL','exit','ato','free','malloc','rand']],
    ['iostream', true  , ['cerr','cout','cin']],
    ['sstream',  true  , ['stringstream']],
    ['vector',   true  , [/vector\s*</]],
    ['map',      true  , [/map\s*</]],
    ['set',      true  , [/set\s*</]],
    ['string',   true  , ['string']],
    ['typeinfo', false , ['typeid']],
  ]
  LINES_THRESHOLD = 1000
  USING_STD       = 'using namespace std;'

  class << self
    def process
      return if $curbuf.length > LINES_THRESHOLD

      begin
        lines = VIM::lines
        includes, content, use_std = [['',0]], '', false

        # split includes and other content
        lines.each_with_index do |l, i|
          if l =~ /#\s*include/
            includes << [l, i+1]
          else
            content << l.gsub(/\/\/[^"]*(?:"[^"']*"[^"]*)*$/,'') << "\n"
          end
        end

        # process each header
        HEADER_STD_KEYWORDS.each do |header, std, keywords|
          has_keyword = keywords.any? { |w| content[w] }
          has_header  = includes.detect { |l| l.first.include? header }
          use_std ||= std && has_keyword

          if has_keyword && !has_header
            VIM::append(includes.last.last, "#include <#{header}>")
          elsif !has_keyword && has_header
            VIM::remove(has_header.last)
          end
        end

        # recalculate includes
        includes = VIM::lines(true).select { |l| l.first =~ /#\s*include/ }

        # append empty line to last #include 
        # or remove top empty lines if no #include
        if includes.empty?
          VIM::remove(1, '')
        else
          VIM::append(includes.last.last, '')
        end

        # add / remove 'using namespace std'
        has_std = content[USING_STD]

        if use_std && !has_std && !includes.empty?
          VIM::append(includes.last.last+1, USING_STD) 
          VIM::append(includes.last.last+2, '')
        elsif !use_std && has_std
          VIM::remove(nil, USING_STD)
          VIM::remove(1, '') if includes.empty?
        end
      rescue => ex
        File.open("/tmp/ex.txt", 'w') { |f| f.puts ex; f.puts ex.backtrace }
        raise RuntimeError.new(ex.message)
      end
    end
  end
end
EOF