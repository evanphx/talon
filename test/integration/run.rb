
Dir.chdir File.dirname(__FILE__)

files = Dir["*.tln"]

fails = false

files.each do |f|
  checks = File.readlines(f).grep(/-- check: (.*)/) { $1 }

  system "ruby -I../../lib ../../bin/talon #{f}"
  if $?.exitstatus != 0
    puts "FAIL (compile) #{f}"
    fails = true
    next
  end

  exe = File.basename f, ".tln"

  out = `./#{exe}`

  if !out
    puts "FAIL (run) #{f}"
    File.unlink exe if File.exists? exe
    fails = true
    next
  end

  output = out.split("\n")

  if checks != output
    puts "FAIL (check) #{f}"
    fails = true
    puts "#{output.inspect} not equal to #{checks.inspect}"
  else
    puts "PASS #{f}"
  end

  File.unlink exe

end

exit 1 if fails
