#!/usr/bin/env ruby

require 'rubygems' # can't find sinatra otherwise
require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/flash'
require 'slim'
require 'sass'
require 'aws-sdk'

enable :sessions
set :bind, '0.0.0.0'
set :logging, true

AWS.config(:credential_provider => AWS::Core::CredentialProviders::EC2Provider.new)
$s3 = AWS::S3.new
$ec2 = AWS::EC2.new(:region => 'us-east-1')
$sns = AWS::SNS.new(:region => 'us-east-1')
$sdb = AWS::SimpleDB.new(:region => 'us-east-1')
$domain = $sdb.domains['contactsdb']
$bucket = $s3.buckets['trialbucketshawn']
$bucket.exists?
$topic_up = $sns.topics['arn:aws:sns:us-east-1:622071431692:51083-updated']
$topic_a = $sns.topics['arn:aws:sns:us-east-1:622071431692:51083-A']
$topic_b = $sns.topics['arn:aws:sns:us-east-1:622071431692:51083-B']
$topic_c = $sns.topics['arn:aws:sns:us-east-1:622071431692:51083-C']
$topics = {"51083-updated" => $topic_up, "51083-A" => $topic_a, "51083-B" => $topic_b, "51083-C" => $topic_c}

VALID_URI_REGEX = /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix
VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
VALID_ALPHABET_REGEX = /^[A-z]+$/i
def uri?(string)
  m = string.match(VALID_URI_REGEX)
  return m != nil
end
def email?(string)
  m = string.match(VALID_EMAIL_REGEX)
  return m != nil
end
def valid_name?(string)
  m = string.match(VALID_ALPHABET_REGEX)
  return m != nil
end

get '/' do
  @keys = []
  $bucket.objects.each do |obj|
    if obj.key.end_with?(".html")
      @keys << obj.key
    end
  end
  slim :home
end

get '/topics' do
  @topic_keys = $topics.each_key
  slim :topics
end

post '/subscribe' do
  key = params[:topickey]
  subscriber = params[:subscriber]
  if uri?(subscriber) || email?(subscriber)
    $topics.fetch(key).subscribe(subscriber)
    flash[:notice] = "#{subscriber} successfully subscribed to #{key}"
  else
    flash[:notice] = "#{subscriber} is neither URI or email"
  end
  redirect to("/topics")
end

get '/contactform' do
  slim :contactform
end

post '/contactcreate' do
  first_name = params[:first_name]
  last_name = params[:last_name]
  #if valid first and last name, create/edit contact
  if valid_name?(first_name) and valid_name?(last_name)
    #S3 behavior
    file_name = "#{first_name}_#{last_name}.html".downcase
    File.open(file_name, 'w') do |file|
      file.write("<table border = \"1\">\n<tr>\n")
      file.write("<th>first_name</th><th>last_name</th></tr>\n<tr>\n")
      file.write("<td>#{first_name}</td><td>#{last_name}</td></tr>\n</table>\n")
    end
    obj = $bucket.objects[file_name]
    obj.write(:file => file_name)
    File.delete(file_name)

    #SimpleDB behavior and creation of sns message/header
    item_name = "#{first_name}_#{last_name}".downcase
    item = $domain.items[item_name]
    if !item.attributes.collect(&:name).empty?
      subject_line = "Contact Edited"
      message = "Contact Edited: " + first_name + " " + last_name
    else
      subject_line = "Contact Created"
      message = "Contact Created: " + first_name + " " + last_name
    end
    item = { :first_name => first_name, :last_name => last_name }
    $domain.items.create item_name, item

    #SNS behavior
    $topic_up.publish(message, :subject => subject_line)

    flash[:notice] = message
  else
    flash[:notice] = "first and last name must both be 1-16 LETTERS"
  end
  redirect to("/")
end

not_found do
  slim :not_found
end

__END__
@@layout
doctype html
html
head
  meta charset="utf-8"
  title CSPP 51083 WebApp
body
  header
    h1 <center>CSPP 51083 WebApp HW7 -- Shawn Stevens</center>
    h1 <center><a href="/" title="Home">Home</a> || <a href="/topics" title="Topics">Topics</a> || <a href="/contactform" title="Contact Form">Contact Form</a></center>
  section
    == styled_flash
    == yield
@@home
h2 Contacts
- @keys.each do |key|
  li <a href="https://s3.amazonaws.com/trialbucketshawn/#{key}">#{key}</a>
@@contactform
h2 Create/Edit Contact
form action="/contactcreate" method="POST"
  label for="first_name" First Name:
  input#first_name type="text" name="first_name" <br>
  label for="last_name" Last Name:
  input#last_name type="text" name="last_name" <br>
  input.button type="submit" value="Submit Contact Info"
@@topics
h2 Topics
- @topic_keys.each do |key|
  form action="/subscribe" method="POST"
    input type="text" name="subscriber"
    input type="hidden" name="topickey" value=key
    input.button type="submit" value="Subscribe to #{key}"
  <br>
@@not_found
h2 Error 404
p Bad link. <a href='/'>Home Page</a>
