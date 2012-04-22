require 'talon/test_case'
require 'rubygems'
require 'kpeg'

module Talon
end

KPeg.load File.expand_path("../../grammar.kpeg", __FILE__), "TestParser"

require 'talon'

