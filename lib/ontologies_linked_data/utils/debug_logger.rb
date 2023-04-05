require 'logger'
class DebugLogger < Logger
  alias write <<

  def flush
    ((self.instance_variable_get :@logdev).instance_variable_get :@dev).flush
  end
end

# Setup global logging
# USAGE:
# - LOGGER.debug("message")
# - LOGGER.error("message")
# - LOGGER.debug("message")
# ============================
#  LOG LEVEL LIST (LOGGER.level)
# ============================
#  FATAL: An unhandleable error that results in a program crash.
#  ERROR: A handleable error condition.
#  WARN : A warning.
#  INFO : Generic (useful) information about system operation.
#  DEBUG: Low-level information for developers.
# If you set one of the log levels above, the upper levels are also included

Dir.mkdir('log') unless File.exist?('log')
log = File.new("log/debug_ont_linked_data.log", "a+")
log.sync = true
ECOPORTAL_LOGGER = DebugLogger.new(log)
ECOPORTAL_LOGGER.level = Logger::DEBUG

