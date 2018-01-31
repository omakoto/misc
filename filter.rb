#!/usr/bin/env ruby

# Helper command for the filter command.

start = []
stop = []

ARGV.each_with_index do |arg, i|
  # puts "index: #{i} - #{arg}"

  re = nil
  if arg.size == 0 or arg == "-"
    re = /^\s*$/
  else
    re = /#{arg}/i
  end

  if i % 2 == 0
    start.push re
  else
    stop.push re
  end
end

#p start
#p stop

showing = (start.size == 0)

cut_printed = false

$stdin.each do |line|
  line.chomp!

  if showing
    stop.each do |re|
      if line =~ re
        showing = false
        break
      end
    end
  else
    start.each do |re|
      if line =~ re
        showing = true
        break
      end
    end
  end

  if showing
    puts line if showing
    cut_printed = false
  else
    if !cut_printed
      puts "-"
      cut_printed = true
    end
  end
end
