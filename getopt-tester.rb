#!/usr/bin/env ruby2.3

require_relative 'getopt'

force = false
title = ""

def usage()
  puts "Usage: $0 AAABBBCCC"
end

# getopt(
#   ["f|force", lambda { force = true }, "Force execute."],
#   ["t|tittle=s", lambda { |x| arg = x }, "Specify title."],
#   # ["n|number=i", lambda { |x| arg = x }, "Specify number."],
#   # take_files: true,
#   );

getopt(
  ["f|force", lambda { force = true }, "Force execute."],
  ["t|title=s", lambda { |x| title = x }, "Specify title."],
  take_files: true,
  usage: lambda {usage}
  );

puts "force=#{force.inspect}"
puts "title=#{title.inspect}"
