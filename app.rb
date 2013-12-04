#!/usr/bin/env ruby

## Diwali Dashboard 
#	Author: Saurajeet Dutta


#Requiring dependencies
require 'rubygems'
require 'sinatra'
require 'tokenizer'
require 'socket'
require 'ruby-debug'

#setting up public assets
set :public_folder, "assets"


#setting some global data for all the views
configure do
	Name = "Diwali Dashboard"
	Version = "0.1"
end


class App < Sinatra::Application
#Url Routes
get '/dash' do
	#Reading Configuration
	appDir = File.expand_path File.dirname(__FILE__)
	appConf = File.expand_path File.dirname(__FILE__), "include"
	Dir["#{appConf}/*.rb"].each {|file| require file }
	debug = false
        @ttConfig = TT::Config.new appDir, "default", debug

	host = @ttConfig.configuration["nagios_host"]
	port = @ttConfig.configuration["nagios_port"]
	dat = ""

	output = `cat data`
	lines = output.split("\n")
	legends = lines[0].split(";")
	@hostgroups = {}
	@tupleIndex = {}
	tupleNumber=0;
	legends.each do |legend|
		@hostgroups[legend.to_sym] = []
		@tupleIndex[tupleNumber.to_s.to_sym] = legend
		tupleNumber = tupleNumber + 1;
	end

	autoCol=0 #Asserting Autocolumn Support for Variable Unlabelled Columns
	#Create the hostgroup table from the output
	@datacount = lines.length-1
	for i in 1..@datacount
		data = lines[i].split(";");
		if (data[26] =~ /rds.amazonaws.com/)
                       next
	        end
		valptr = 0
		data.each do |val|
			if @tupleIndex[valptr.to_s.to_sym] == nil
				@tupleIndex[valptr.to_s.to_sym] = "AutoColumn#{autoCol}"
				@hostgroups["AutoColumn#{autoCol}".to_sym] = []
				#puts "DEBUG: CREATING COL = #{autoCol}"
				autoCol = autoCol + 1
			end
			if val!=nil
				@hostgroups[@tupleIndex[valptr.to_s.to_sym].to_sym] << val
			else
				@hostgroups[@tupleIndex[valptr.to_s.to_sym].to_sym] << "NULLDATA"
			end	
			valptr = valptr + 1
		end
	end

	#Some Tuple Numbers
	@host_name=26
	@cluster_name=39
	@check_list=133
 	@status_string=134
	
	#SOME DATA REQUIRED FOR PROCESSING
	@nf_check = @ttConfig.configuration["non_functionality_checks"]
	@pageData = {}
	@clusterHealth={}
	@health = []
	exclude_list = @ttConfig.configuration["exclude_checks"]
	skip = false #This value is used to read clean lines from the output
	
	@datacount = @hostgroups[@tupleIndex[@check_list.to_s.to_sym].to_sym].length
	
	#START PROCESSING ALL HOSTS IN THE DS
	for hosts in 0..@datacount-1
		#CREATE HOST HEALTH DATASTRUCTURE
		cHealth = {:clustername=> "", :nodecount=>"", :status=>"", :healthynodes=>"", :sicknodes=>""}
		nodeHealth = {:hostname=>"", :index=>"", :status=>""}
		
		#CREATE PAGE DATA FOR VISUALIZING
		c_name = @hostgroups[@tupleIndex[@cluster_name.to_s.to_sym].to_sym][hosts]
		h_name = @hostgroups[@tupleIndex[@host_name.to_s.to_sym].to_sym][hosts]
		
		#LOG ANY INCONSISTENCY FOUND AND TRY TO MAKE PAGEDATA APPROPRIATELY CHANGABLE
		if c_name == nil 
			puts "DEBUG: Null Cluster Name found for tuple##{hosts}, col##{@cluster_name}"
			skip = true
		elsif h_name == nil
			puts "DEBUG: Null Hostname found for tuple##{hosts}, col##{@host_name}"
			skip=true
		end
		
		if @pageData[c_name] == nil
			@pageData[c_name] = []
		end
		if c_name != nil and h_name != nil
			#@pageData[c_name.to_sym] << h_name
		end

		#if skip is true, forfiet calculation of nodehealth, its a dirty data
		if skip == true
			next
		end

		#else calculate the node health
		status = @hostgroups[@tupleIndex[@status_string.to_s.to_sym].to_sym][hosts]
		
		#CREATE CHECK PARSING DATASTRUCTURE
		@all_check = @hostgroups[@tupleIndex[@check_list.to_s.to_sym].to_sym][hosts].split(",")
		@f_check = @all_check - @nf_check
		check_status = status.split(",")

		detailedHealth = {}
		detailedHealth["hostname"] = h_name

		hoststatus="green"
		check_status.each do |checkstatus|
			cstatus = checkstatus.split("|")
			#check if it is a functionality check
			invalidCheck=false

			#ignoring MemUsage for now			
			if exclude_list.include? cstatus[0]
				next
			end

			if @f_check.include?(cstatus[0])
				if (cstatus[1] == "0")
				else
					hoststatus="red"
				end				
			elsif @nf_check.include?(cstatus[0])
				if (cstatus[1] == "0")
				else
					if hoststatus!="red" or hoststatus=="green"
						hoststatus="orange"
					end
				end	
			else
				invalidCheck = true	## there is some dirty elements here
			end
		
			#Filling up data for the interface to access
			if cstatus[1] == "0" and invalidCheck==false
				detailedHealth[cstatus[0]] = "PASS #{cstatus[3]}"
			elsif invalidCheck == false
				#ignoring Metric MemUsage for now
				if cstatus[0] == "Mem Usage"
					detailedHealth[cstatus[0]] = "PASS #{cstatus[3]}"
				else
					detailedHealth[cstatus[0]] = "FAIL #{cstatus[3]}"
				end
			end
		end
		
		#Contruct Node Health
		nodeHealth[:hostname] = h_name
		nodeHealth[:index] = hosts.to_s
		nodeHealth[:status] = hoststatus


		@health[hosts] =  detailedHealth.dup

		@pageData[c_name] << nodeHealth.dup

		#COMPUTE CLUSTER HEALTH
		cHealth[:clustername] = c_name
		cHealth[:nodecount] = @pageData[c_name].size

			#define minThreshold = x
				x = 1
			#define maxThreshold = y
				y = cHealth[:nodecount] - 1
		redServers = 0	
		@pageData[c_name].each do |hs|
			if hs[:status] == 'red'
				redServers = redServers +1
			end	
		end

		if redServers > x and redServers <= y
			cHealth[:status] = "orange"
		elsif redServers > y
			cHealth[:status] = "red"
		else
			cHealth[:status] = "green"
		end
		cHealth[:sicknodes] = redServers
		cHealth[:healthynodes] = cHealth[:nodecount] - cHealth[:sicknodes]

		@clusterHealth[c_name] = cHealth.dup
	end

	#pp @pageData	
	if params[:d]=="t"
		erb :dump
	else
		erb :dash
	end
end

get '/' do
	erb :test
end

get '/jk' do
	erb :jk
end
end
