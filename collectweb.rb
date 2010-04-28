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

get '/test' do
  haml :graph, :layout => :test
end

get '/' do
  hosts = hostnames
  hosts.join("<br />")
end
get '/graph/:hostname/:service/:id/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:service]
      content_type "image/png"

      data = YAML::load(File.open("#{options.confdir}#{params[:service]}.yaml"))

      args = []
      args << "rrdtool"
      args << "graph"
      args << "-"
      args << "--title #{data["title"]}"
      args << "--width #{data["width"]}"
      args << "--height #{data["height"]}"
      
      if data["alt_y_grid"]
        args << "--alt-y-grid"
      end

      data["values"].each { |value|
        if data["single_file"]
          args << "DEF:#{value["name"]}=#{options.rrddir}#{params[:hostname]}/#{params[:service]}-#{params[:id]}/#{data["rrds"]}.rrd:#{value["ds"]}:AVERAGE"
        else
          args << "DEF:#{value["name"]}=#{options.rrddir}#{params[:hostname]}/#{params[:service]}-#{params[:id]}/#{data["rrds"]}-#{value["name"]}.rrd:#{value["ds"]}:AVERAGE"
        end

        if value["cdef"].nil?
          val_to_graph = value["name"]
        else
          value["cdef"].each { |cdef|
            args << "CDEF:#{cdef["name"]}=#{cdef["rpn"]}"
            if cdef["graph"]
              val_to_graph = cdef["name"]
            end
          }
        end

        if value["stacked"]
          args << "#{value["type"]}:#{val_to_graph}##{value["color"]}:\"#{value["text"]}\\t\":STACK"
        else
          args << "#{value["type"]}:#{val_to_graph}##{value["color"]}:\"#{value["text"]}\\t\""
        end
        
        args << "GPRINT:#{val_to_graph}:LAST:\"\\tCur\\: %2.1lf\\g\""
        args << "GPRINT:#{val_to_graph}:AVERAGE:\"\\tAvg\\: %2.1lf\\g\""
        args << "GPRINT:#{val_to_graph}:MAX:\"\\tMax\\: %2.1lf\\j\""
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

get '/graph/:hostname/:service/?' do
  if hostnames.include? params[:hostname]
    if host_services(params[:hostname]).keys.include? params[:service]
      content_type "image/png"
      data = YAML::load(File.open("#{options.confdir}#{params[:service]}.yaml"))

      args = []
      args << "rrdtool"
      args << "graph"
      args << "-"
      args << "--title #{data["title"]}"
      args << "--width #{data["width"]}"
      args << "--height #{data["height"]}"

      if data["alt_y_grid"]
        args << "--alt-y-grid"
      end

      data["values"].each { |value|
        if data["single_file"]
          args << "DEF:#{value["name"]}=#{options.rrddir}#{params[:hostname]}/#{params[:service]}/#{data["rrds"]}.rrd:#{value["ds"]}:AVERAGE"
        else
          args << "DEF:#{value["name"]}=#{options.rrddir}#{params[:hostname]}/#{params[:service]}/#{data["rrds"]}-#{value["name"]}.rrd:#{value["ds"]}:AVERAGE"
        end

        if value["cdef"].nil?
          val_to_graph = value["name"]
        else
          value["cdef"].each { |cdef|
            args << "CDEF:#{cdef["name"]}=#{cdef["rpn"]}"
            if cdef["graph"]
              val_to_graph = cdef["name"]
            end
          }
        end

        if value["stacked"]
          args << "#{value["type"]}:#{val_to_graph}##{value["color"]}:\"#{value["text"]}\\t\":STACK"
        else
          args << "#{value["type"]}:#{val_to_graph}##{value["color"]}:\"#{value["text"]}\\t\""
        end
        args << "GPRINT:#{val_to_graph}:LAST:\"\\tCur\\: %2.1lf#{'%s' if value["si_units"]}\\g\""
        args << "GPRINT:#{val_to_graph}:AVERAGE:\"\\tAvg\\: %2.1lf#{'%s' if value["si_units"]}\\g\""
        args << "GPRINT:#{val_to_graph}:MAX:\"\\tMax\\: %2.1lf#{'%s' if value["si_units"]}\\j\""
      }

      puts args.join(" ")
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

