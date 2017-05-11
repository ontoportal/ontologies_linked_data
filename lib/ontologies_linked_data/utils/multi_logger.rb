require 'omni_logger'

module LinkedData::Utils
  class MultiLogger < OmniLogger
    def flush()
      @loggers.each { |logger| logger.flush }
    end
  end
end