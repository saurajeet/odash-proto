require 'rubygems'
require 'yaml'
module TT
	class Config	
		attr_reader :access_key, :secret_key, :user, :configFile, :configPath
		attr_accessor :configuration
		def initialize (path, config_file="default", debug=false)
			@configFile = config_file
			@configPath = path+ "/config"
		 	puts "CONFIG:: Reading from #{@configPath}/#{@configFile}.yml" if (debug)
			@configuration = YAML.load_file "#{@configPath}/#{@configFile}.yml"
			puts "CONFIG:: #{@configuration.inspect if (debug)}"
			@access_key = configuration[:ak]
			@secret_key = configuration[:sc]
		end
		
	end
end
