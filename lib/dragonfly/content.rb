require 'base64'
require 'forwardable'
require 'dragonfly/has_filename'
require 'dragonfly/temp_object'
require 'dragonfly/utils'

module Dragonfly
  class Content

    include HasFilename
    extend Forwardable

    def initialize(app, obj="", meta=nil)
      @app = app
      @meta = {}
      @previous_temp_objects = []
      update(obj, meta)
    end

    attr_reader :app
    def_delegators :app,
                   :analyser, :generator, :processor, :shell, :datastore, :env

    attr_reader :temp_object
    attr_accessor :meta
    def_delegators :temp_object,
                   :data, :file, :path, :to_file, :size, :each, :to_file, :to_tempfile

    def name
      meta["name"] || temp_object.original_filename
    end

    def name=(name)
      meta["name"] = name
    end

    def mime_type
      app.mime_type_for(ext)
    end

    def generate!(name, *args)
      app.get_generator(name).call(self, *args)
      self
    end

    def process!(name, *args)
      app.get_processor(name).call(self, *args)
      self
    end

    def analyse(name)
      analyser_cache[name.to_s] ||= app.get_analyser(name).call(self)
    end

    def update(obj, meta=nil)
      self.temp_object = TempObject.new(obj)
      original_filename = temp_object.original_filename
      self.meta['name'] ||= original_filename if original_filename
      self.meta.delete("analyser_cache")
      add_meta(meta) if meta
      self
    end

    def add_meta(meta)
      self.meta.merge!(meta)
      self
    end

    def shell_eval(opts={})
      should_escape = opts[:escape] != false
      command = yield(should_escape ? shell.quote(path) : path)
      run command, :escape => should_escape
    end

    def shell_generate(opts={})
      ext = opts[:ext] || self.ext
      should_escape = opts[:escape] != false
      tempfile = Utils.new_tempfile(ext)
      new_path = should_escape ? shell.quote(tempfile.path) : tempfile.path
      command = yield(new_path)
      run(command, :escape => should_escape)
      update(tempfile)
    end

    def shell_update(opts={})
      ext = opts[:ext] || self.ext
      should_escape = opts[:escape] != false
      tempfile = Utils.new_tempfile(ext)
      old_path = should_escape ? shell.quote(path) : path
      new_path = should_escape ? shell.quote(tempfile.path) : tempfile.path
      command = yield(old_path, new_path)
      run(command, :escape => should_escape)
      update(tempfile)
    end

    def store(opts={})
      datastore.write(self, opts)
    end

    def b64_data
      "data:#{mime_type};base64,#{Base64.encode64(data)}"
    end

    def close
      previous_temp_objects.each{|temp_object| temp_object.close }
      temp_object.close
    end

    private

    attr_reader :previous_temp_objects
    def temp_object=(temp_object)
      previous_temp_objects.push(@temp_object) if @temp_object
      @temp_object = temp_object
    end

    def analyser_cache
      meta["analyser_cache"] ||= {}
    end

    def run(command, opts)
      Dragonfly.info("Running Command: #{command}") if app.log_shell
      shell.run(command, opts)
    end

  end
end

