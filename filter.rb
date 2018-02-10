#!/usr/bin/env ruby

# Helper command for the filter command.

color = true && (ENV['FILTER_NO_COLOR'] != "1")

gray_start = color ? "\e[32m" : ""
gray_end = color ? "\e[0m" : ""


start = []
stop = []
one_shot = []

next_start = true

ARGV.each_with_index do |arg, i|
  # puts "index: #{i} - #{arg}"

  re = nil
  if arg.size == 0 or arg == "-"
    re = /^\s*$/
  elsif arg.start_with? "@"
    re = /#{arg[1..-1]}/i
    one_shot.push(re)
    next
  else
    re = /#{arg}/i
  end

  if next_start
    start.push re
  else
    stop.push re
  end
  next_start = !next_start
end

#p start
#p stop

showing = false

skipped_lines = 0
start_index = -1

$stdin.each do |line|
  print_line = false
  catch :next_line do
    line.chomp!

    if !showing
      start.each_with_index do |re, i|
        if line =~ re
          showing = true
          start_index = i
          break
        end
      end
    else
      if start_index >= 0 && stop[start_index]
        re = stop[start_index]
        if line =~ re
          showing = false
          print_line = true
          throw :next_line
        end
      end
    end

    if showing
      print_line = true
      throw :next_line
    end
    one_shot.each do |re|
      if line =~ re
        print_line = true
        throw :next_line
      end
    end
  end
  if print_line || $stdin.eof?
    puts "#{gray_start}#[#{skipped_lines} line(s) skipped]#{gray_end}" if skipped_lines > 0
  end

  if print_line
    puts line
    skipped_lines = 0
  else
    skipped_lines += 1
  end
end
