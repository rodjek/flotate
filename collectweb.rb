require 'rubygems'
require 'sinatra'
require 'open3'
require 'yaml'

set :rrddir, "/home/tim/collectweb/rrd/" 
set :confdir, "etc/"
set :public, "public/"

not_found do
  "Oh noes, a 404"
end

get '/' do
  hosts = hostnames
  hosts.join("<br />")
end

get '/:hostname/?' do
  if hostnames.include? params[:hostname]
    services = host_services params[:hostname]
    services.keys.join("<br />")
  else
    status 404
  end
end

get '/:hostname/:service/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:service]
      graphs = host_services(params[:hostname])[params[:service]]
      @data = []
      if graphs.empty?
        @data << {:title => params[:service], :graphs => ["/graph/#{params[:hostname]}/#{params[:service]}/"]}
      else
        graphs.each { |key|
          @data << {:title => "#{params[:service]}-#{key}", :graphs => ["/graph/#{params[:hostname]}/#{params[:service]}/#{key}/"]}
        }
      end
      haml :graph, :layout => :test
    else
      status 404
    end
  else
    status 404
  end
end

get '/data/:hostname/:service/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:service]
      config = YAML::load(File.open("#{options.confdir}#{params[:service]}.yaml"))
      args = []

      args << "rrdtool"
      args << "xport"
      args << "--start" << params[:start]
      args << "--end" << (params[:end].nil? ? "now" : params[:end])

      config["datasources"].each { |datasource|
        args << "DEF:#{datasource["name"]}=#{options.rrddir}#{params[:hostname]}/#{params[:service]}/#{datasource["rrd"]}:#{datasource["ds"]}:AVERAGE"
        args << "XPORT:#{datasource["name"]}:\"#{datasource["title"]}\""
      }

      Open3.popen3(args.join(" ")) { |stdin, stdout, stderr|
        stdout.read()
      }
    else
      status 404
    end
  else
    status 404
  end
end

helpers do
  def hostnames()
    hosts = Dir.new(options.rrddir).entries
    hosts.delete(".")
    hosts.delete("..")
    hosts
  end

  def host_services(hostname)
    services = Dir.new("#{options.rrddir}/#{hostname}").entries
    services.delete(".")
    services.delete("..")
    services.sort!
    data = {}
    services.each { |service|
      foo = service.split('-')
      data[foo[0]] ||= []
      if foo.length > 1
        data[foo[0]]  << foo[1]
      end
    }
    data
  end
end

