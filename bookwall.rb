#!/usr/bin/ruby

# usage : ./bookwall username
#http://www.douban.com/people/username/

require "mechanize"
#require 'nokogiri'  
#require 'open-uri'

if ARGV.size != 1
	print "usage: ./bookwall username\n"
	exit -1 
end 

$name = ARGV[0] 
$uri = sprintf("http://book.douban.com/people/%s/collect?start=0&sort=time&rating=all&filter=all&mode=grid", $name);

agent = Mechanize.new
page = agent.get($uri)

$book = File.new("bookwall.html", "w+")
if $book == nil
	exit -1
end
$book.printf("<title>%s's Book</title>", $name)
$book.puts "<body bgcolor=\"#eee\">"

$page = page
begin 
	page = agent.click($page)
	pp page
	page.links_with(:class => 'nbg').each do |link|
#		if !link.href.include?"buylink"
		$book.puts link.node
#		end
	end
	sleep 3
	$page = page.links.find {|l| l.text == '后页>'}
end while $page  
$book.printf("<hr></p>NOTE: These are the books @%s ever read, listed by the date when it got finished.</p>",$name)
$book.close

=begin

# get the titles of all books 
begin 
	$flag = false
	doc = Nokogiri::HTML(open($uri))
	doc.css('a').each do |link|  
		if link['title']
			if link['href'].include?"subject"
    			puts link['title']
			end
		end	

		if link.text == '后页>'
			$uri = link['href']
			$flag = true
		end
	end
	sleep 3
end while $flag
=end
