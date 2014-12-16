module SAXMachine
  def self.included(base)
    base.send(:include, InstanceMethods)
    base.extend(ClassMethods)
  end

  def parse(xml_text, on_error = nil, on_warning = nil)
    handler_klass = SAXMachine.const_get("SAX#{SAXMachine.handler.capitalize}Handler")

    handler = handler_klass.new(self, on_error, on_warning)
    handler.sax_parse(xml_text)

    self
  end

  module InstanceMethods
    def initialize(attributes = {})
      attributes.each do |name, value|
        send("#{name}=", value)
      end

      self.class.sax_config.top_level_elements.each do |_, configs|
        configs.each do |config|
          next unless config.default
          next unless send(config.as).nil?

          send(config.setter, config.default)
        end
      end
    end
  end

  module ClassMethods
    def inherited(subclass)
      subclass.sax_config.send(:initialize_copy, self.sax_config)
    end

    def parse(*args)
      new.parse(*args)
    end

    def element(name, options = {}, &block)
      real_name = (options[:as] ||= name).to_s
      sax_config.add_top_level_element(name, options)
      create_attr(real_name, &block)
    end

    def attribute(name, options = {}, &block)
      real_name = (options[:as] ||= name).to_s
      sax_config.add_top_level_attribute(self.class.to_s, options.merge(name: name))
      create_attr(real_name, &block)
    end

    def value(name, options = {})
      real_name = (options[:as] ||= name).to_s
      sax_config.add_top_level_element_value(self.class.to_s, options.merge(name: name))
      create_attr(real_name)
    end

    def ancestor(name, options = {})
      real_name = (options[:as] ||= name).to_s
      sax_config.add_ancestor(name, options)
      create_attr(real_name)
    end

    def columns
      sax_config.columns
    end

    def column(sym)
      columns.select { |c| c.column == sym }[0]
    end

    def data_class(sym)
      column(sym).data_class
    end

    def required?(sym)
      column(sym).required?
    end

    def column_names
      columns.map { |e| e.column }
    end

    def elements(name, options = {})
      options[:as] ||= name

      if options[:class]
        sax_config.add_collection_element(name, options)
      else
        class_eval <<-SRC
          def add_#{options[:as]}(value)
            #{options[:as]} << value
          end
        SRC
        sax_config.add_top_level_element(name, options.merge(collection: true))
      end

      if !method_defined?(options[:as].to_s)
        class_eval <<-SRC
          def #{options[:as]}
            @#{options[:as]} ||= []
          end
        SRC
      end

      attr_writer(options[:as]) unless method_defined?("#{options[:as]}=")
    end

    def sax_config
      @sax_config ||= SAXConfig.new
    end

    # we only want to insert the getter and setter if they haven't defined it from elsewhere.
    # this is how we allow custom parsing behavior. So you could define the setter
    # and have it parse the string into a date or whatever.
    def create_attr(real_name, &block)
      attr_reader(real_name) unless method_defined?(real_name)

      if !method_defined?("#{real_name}=")
        if block_given?
          define_method("#{real_name}=") do |value|
             instance_variable_set("@#{real_name}", (yield value))
          end
        else
          attr_writer(real_name)
        end
      end
    end
  end
end
