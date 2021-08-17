" Copyright (C) 2012 WU Jun <quark@zju.edu.cn>
" 
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
" 
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
" 
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.

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
        break if i >= $curbuf.length
      end
    end
  end
end


module CppAutoInclude
  # shortcut to generate regex
  C = proc do |*names| names.map { |name| /\b#{name}\b/ } end
  F = proc do |*names| names.map { |name| /\b#{name}\s*\(/ } end
  # Replaced T by C to recognize CTAD
  # T = proc do |*names| names.map { |name| /\b#{name}\s*<\b/ } end
  T = proc do |*names| names.map { |name| /\b#{name}\b/ } end
  R = proc do |*regexs| Regexp.union(regexs.flatten) end

  # TODO: add C++17 features and ext/pb_ds/ includes. Note that this is not complete, it is just a small subset that is convenient
  # header, std namespace, keyword complete (false: no auto remove #include), unioned regex
  HEADER_STD_COMPLETE_REGEX = [
    ['tuple',                           true,  true , R[F['make_tuple', 'tie', 'forward_as_tuple', 'tuple_cat', 'apply', 'make_from_tuple'], C['get', 'tuple', 'tuple_size', 'tuple_element', 'uses_allocator', 'ignore']] ], # tie in streams is a false positive
    ['cstdio',                          false, true , R[F['s?scanf', 'puts', 's?printf', 'fgets', '(?:get|put)char', 'getc'], C['FILE','std(?:in|out|err)','EOF']] ],
    ['cassert',                         false, true , R[F['assert']] ],
    ['cstring',                         false, true , R[F['mem(?:cpy|set|move|chr|n?cmp)', 'str(?:len|n?cmp|n?cpy|error|cat|str|chr)']] ],
    ['cstdlib',                         false, true , R[F['system','abs','ato[if]', 'itoa', 'strto[dflu]+','free','exit','l?l?abs','s?rand(?:_r|om)?','qsort'], C['EXIT_[A-Z]*', 'NULL']] ],
    ['cmath',                           false, true , R[F['pow[fl]?','a?(?:sin|cos|tan)[hl]*', 'atan2[fl]?', 'exp[m12fl]*', 'fabs[fl]?', 'log[210fl]+', 'nan[fl]?', '(?:ceil|floor)[fl]?', 'l?l?round[fl]?', 'sqrt[fl]?', 'cbrt[fl]?', 'hypot[fl]?'], C['M_[A-Z24_]*', 'NAN', 'INFINITY', 'HUGE_[A-Z]*']] ],
    ['strings.h',                       false, true , R[F['b(?:cmp|copy|zero)', 'strn?casecmp']] ],
    ['typeinfo',                        false, true , R[C['typeid', 'bad_typeid', 'bad_cast']] ],
    ['type_traits',                     false, true , R[C['(?:integral|bool)_constant', 'is_[a-z_]*', 'enable_if', 'void_t', 'common_type', 'decay']] ], # is_sorted is a false positive
    ['new',                             true , true , R[F['set_new_handler'], C['nothrow']] ],
    ['limits',                          true , true , R[T['numeric_limits']] ],
    ['algorithm',                       true , true , R[F['(?:stable_|partial_)?sort(?:_copy)?', 'unique(?:_copy)?', 'reverse(?:_copy)?', 'nth_element', '(?:lower|upper)_bound', 'binary_search', '(?:prev|next)_permutation', 'min(?:max)?(?:_element)?', 'max(?:_element)?', 'count', '(?:random_)?shuffle', '(?:iter)?swap(?:_ranges)?', '(?:all|any|none)_of', 'for_each(?:_n)?', 'count(?:if)?', 'mismatch', 'find(?:_if(?:_not)?|end)?', 'find_first_of', 'adjacent_find', 'search(?:_n)?', 'copy(?:_if|_n|_backward)?', 'move(?:_backward)?', 'fill(?:_n)?', 'transform', 'generate(?:_n)?', '(?:replace|remove|reverse|rotate)(?:copy)?(?:_if)?', 'sample', 'shift_(?:left|right)', '[a-z_]*partition[a-z_]*', 'is_sorted[a-z_]*', 'equal_range', 'set_[a-z_]*', '[a-z_]*heap[a-z_]*', 'clamp', 'equal', 'lexicographical_compare']] ],
    ['numeric',                         true , true , R[F['partial_sum', 'accumulate', 'adjacent_difference', 'inner_product', 'iota', 'reduce', 'transform_reduce', 'gcd', 'lcm', '(?:transform)?(?:inclusive|exclusive)_scan']] ],
    ['iostream',                        true , true , R[C['c(?:err|out|in)']] ],
    ['sstream',                         true , true , R[C['[io]?stringstream']] ],
    ['bitset',                          true , true , R[T['bitset']] ],
    ['chrono',                          true , true , R[C['std::chrono::duration', 'std::chrono::time_point', 'std::chrono::system_clock', 'std::chrono::steady_clock', 'std::chrono::high_resolution_clock']] ],
    ['functional',                      true , true , R[C['function', 'bind', 'c?ref', 'invoke[_r]+', 'plus', 'minus', 'multiplies', 'divides', 'modulus', 'negate', 'equal_to', 'not_equal_to', 'greater', 'less', 'greater_equal', 'less_equal', 'logical_(?:and|or|not)', 'bit_(?:and|or|not|xor)', 'not_fn', 'default_searcher', 'boyer_moore_[a-z]*_searcher'], F['hash']] ],
    ['optional',                        true , true , R[C['optional', 'nullopt'], F['make_optional']] ],
    ['complex',                         true , true , R[T['complex']] ],
    ['deque',                           true , true , R[T['deque']] ],
    ['stack',                           true , true , R[T['stack']] ],
    ['queue',                           true , true , R[T['queue','priority_queue']] ],
    ['list',                            true , true , R[T['list']] ],
    ['map',                             true , true , R[T['(?:multi)?map']] ],
    ['unordered_map',                   true , true , R[T['unordered_(?:multi)?map']] ],
    ['set',                             true , true , R[T['(?:multi)?set']] ],
    ['unordered_set',                   true , true , R[T['unordered_(?:multi)?set']] ],
    ['vector',                          true , true , R[T['vector']] ],
    ['iomanip',                         true , true , R[F['setprecision', 'setbase', 'setw'], C['fixed', 'hex']]],
    ['fstream',                         true , true , R[T['fstream']] ],
    ['ctime',                           false, true , R[F['time', 'clock'], C['CLOCKS_PER_SEC']]],
    ['string',                          true , true , R[C['string'], F['sto(?:i|l|ll|ul|ull|f|d|ld)', 'to_string']] ],
    ['utility',                         true , true , R[T['pair', 'integer_sequence'], F['make_pair', 'swap', 'exchange', 'forward', 'move', 'move_if_noexcept', 'as_const', 'declval']] ],
    ['memory',                          true , true , R[T['unique_ptr', 'weak_ptr', 'shared_ptr'], F['addressof', 'align', 'uninitialized_[a-z_]*', 'make_(?:unique|shared)']] ],
    ['cstdint',                         true , true , R[C['u?int[a-z0-9_]*_t', 'U?INT[A-Z0-9_]*']] ],
    ['cctype',                          true , true , R[F['isalnum', 'isalpha', 'islower', 'isupper', 'isdigit', 'isxdigit', 'iscntrl', 'isgraph', 'isspace', 'isblank', 'isprint', 'ispunct', 'tolower', 'toupper']] ],
    ['iterator',                        true , true , R[F['[a-z_]*_iterator', '[a-z_]*inserter', 'advance', 'distance', 'next', 'prev', 'c?r?(?:begin|end)', 'size', 'empty']] ],
    ['array',                           true , true , R[C['array']] ],
    ['ext/pb_ds/assoc_container.hpp',   true , true , R[C['__gnu_pbds']]],
    ['ext/pb_ds/tree_policy.hpp',       true , true , R[C['__gnu_pbds']]],
  ]

  USING_STD       = 'using namespace std;'

  # do nothing if lines.count > LINES_THRESHOLD
  LINES_THRESHOLD = 10000

  class << self
    def includes_and_content
      # split includes and other content
      includes, content = [['', 0]], ''
      VIM::lines.each_with_index do |l, i|
        # use the below regex to parse includes that don't start on a line
        # if l =~ /^\s*#\s*include/
        if l =~ /^#\s*include/
          includes << [l, i+1]
        else
          content << l.gsub(/\/\/[^"]*(?:"[^"']*"[^"]*)*$/,'') << "\n"
        end
      end
      [includes, content]
    end

    def process
      return if $curbuf.length > LINES_THRESHOLD

      begin
        use_std, includes, content = false, *includes_and_content

        # process each header
        HEADER_STD_COMPLETE_REGEX.each do |header, std, complete, regex|
          has_header  = includes.detect { |l| l.first.include? "<#{header}>" }
          has_keyword = (has_header && !complete) || (content =~ regex)
          use_std ||= std && has_keyword

          if has_keyword && !has_header
            VIM::append(includes.last.last, "#include <#{header}>")
            includes = includes_and_content.first
          # elsif !has_keyword && has_header && complete
          #   VIM::remove(has_header.last)
          #   includes = includes_and_content.first
          end
        end

        # append empty line to last #include 
        # or remove top empty lines if no #include
        if includes.last.last == 0
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
          VIM::remove(1, '') if includes.last.last == 0
        end
      rescue => ex
        # VIM hide backtrace information by default, re-raise with backtrace
        raise RuntimeError.new("#{ex.message}: #{ex.backtrace}")
      end
    end
  end
end
EOF

" vim: nowrap
