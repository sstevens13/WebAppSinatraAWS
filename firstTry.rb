#!/usr/bin/env ruby

require 'sinatra'
require 'sinatra/reloader' if development?
require 'slim'
require 'sass'

require 'aws-sdk'

AWS.config(:credential_provider => AWS::Core::CredentialProviders::EC2Provider.new)

set :bind, '0.0.0.0'
set :logging, true

get '/' do
	slim :home
end

__END__
@@home
h2 home
p Placeholder