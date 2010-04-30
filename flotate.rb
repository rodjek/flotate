require 'rubygems'
require 'sinatra'
require 'open3'
require 'yaml'
require 'active_support'
require 'json'

set :rrddir, "rrd/" 
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
    p services
  else
    status 404
  end
end

get '/:hostname/:plugin/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:plugin]
      graphs = new_host_services(params[:hostname])[params[:plugin]]
      @data = []
      if graphs[:no_instances]
        types = graphs.keys
        types.delete(:no_instances)
        if types
          types.each { |type|
            if graphs[type].empty?
              @data << {:title => params[:plugin], :url => "/data/#{params[:hostname]}/#{params[:plugin]}/", :key => params[:plugin]}
            else
              graphs[type].each { |type_instance|
                @data << {:title => "#{type} #{type_instance}", :url => "/data/#{params[:hostname]}/#{params[:plugin]}/", :type => type, :type_instance => type_instance, :key => "#{type}_#{type_instance}"}
              }
            end
          }
        end
        p @data
      else
        # FIXME!  FOR FUCKS SAKE, FIXME!
        graphs.keys.each { |plugin_instance|
          @data << {:title => "#{params[:service]}_#{key}", :plugin_instance => key, :graphs => ["/graph/#{params[:hostname]}/#{params[:service]}/#{key}/"]}
        }
      end
      @end = (params[:end].nil? ? "now" : params[:end])
      @start = (params[:start].nil? ? "now-24h" : params[:start])
      @hostname = params[:hostname]
      @service = params[:service]
      p @data
      haml :graph, :layout => :test
    else
      status 404
    end
  else
    status 404
  end
end

get '/data/:hostname/:plugin/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:plugin]
      config = YAML::load(File.open("#{options.confdir}#{params[:plugin]}.yaml"))
      args = []

      @end = (params[:end].nil? ? "now" : params[:end])
      args << "rrdtool"
      args << "xport"
      args << "--start" << params[:start]
      args << "--end" << @end

      if params[:plugin_instance]
        service = "#{params[:plugin]}-#{params[:plugin_instance]}"
      else
        service = params[:plugin]
      end

      if config.is_a? Array
        if params[:type]
          config = config.reject! { |r| r["type"] != params[:type] }.first
        end
      end

      config["datasources"].each { |datasource|
        if params[:type_instance]
          raw_rrd = datasource["rrd"].split('.')
          rrd = "#{raw_rrd[0]}-#{params[:type_instance]}.rrd"
        else
          rrd = datasource["rrd"]
        end

        args << "DEF:#{datasource["name"]}=#{options.rrddir}#{params[:hostname]}/#{service}/#{rrd}:#{datasource["ds"]}:AVERAGE"
        args << "XPORT:#{datasource["name"]}:\"#{datasource["title"]}\""
      }

      puts args.join(" ")
      Open3.popen3(args.join(" ")) { |stdin, stdout, stderr|
        data = Hash.from_xml(stdout.read())
        result = {}
        result[:start] = "#{data["xport"]["meta"]["start"]}000".to_i
        result[:end] = "#{data["xport"]["meta"]["start"]}000".to_i
        result[:graph_opts] = config["graph_opts"]
        data["xport"]["meta"]["legend"]["entry"].each { |entry|
          ds_config = config["datasources"].reject { |datasource| datasource["title"] != entry }.first
          index = data["xport"]["meta"]["legend"]["entry"].index entry
          values = data["xport"]["data"]["row"].map { |r| ["#{r["t"]}000".to_i, r["v"][index].to_f] }
          (result[:data] ||= []) << {:label => entry, :data => values}.merge(ds_config["plot"])
        }
        result.to_json
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
      plugin, plugin_instance = service.split('-')
      data[plugin] ||= {}
      if plugin_instance
        data[plugin][plugin_instance] ||= true
      end
    }
    data
  end

  def new_host_services(hostname)
    plugins = Dir.new("rrd/#{hostname}").entries
    plugins.delete(".")
    plugins.delete("..")
    plugins.sort!
    data = {}
    plugins.each { |raw_plugin|
      plugin, plugin_instance = raw_plugin.split('-')
      data[plugin] ||= {}
      if plugin_instance
        data[plugin][plugin_instance] ||= {}
        types = Dir.new("rrd/#{hostname}/#{plugin}-#{plugin_instance}").entries
        types.delete(".")
        types.delete("..")
        types.sort!
        types.each { |raw_type|
          type, type_instance = raw_type.split("-")
          data[plugin][plugin_instance][type] ||= []
          if type_instance
            data[plugin][plugin_instance][type] << type_instance.split('.')[0]
          end
        }
      else
        data[plugin][:no_instances] = true
        types = Dir.new("rrd/#{hostname}/#{plugin}").entries
        types.delete(".")
        types.delete("..")
        types.sort!
        types.each { |raw_type|
          type, type_instance = raw_type.split("-")
          if type_instance
            data[plugin][type] ||= []
            data[plugin][type] << type_instance.split('.')[0]
          else
            data[plugin][type.split('.')[0]] ||= []
          end
        }
      end
    }
    data
  end
end

