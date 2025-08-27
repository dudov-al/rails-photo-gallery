# Performance monitoring and benchmarking utilities
class PerformanceMonitor
  include Singleton
  
  def initialize
    @metrics = {}
    @slow_queries = []
    @memory_usage = []
  end
  
  def self.benchmark(name, &block)
    instance.benchmark(name, &block)
  end
  
  def self.log_slow_query(sql, duration)
    instance.log_slow_query(sql, duration)
  end
  
  def self.track_memory_usage(label = nil)
    instance.track_memory_usage(label)
  end
  
  def self.report
    instance.generate_report
  end
  
  def benchmark(name, &block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    start_memory = memory_usage_mb
    
    result = yield
    
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end_memory = memory_usage_mb
    
    duration = end_time - start_time
    memory_delta = end_memory - start_memory
    
    @metrics[name] ||= []
    @metrics[name] << {
      duration: duration,
      memory_delta: memory_delta,
      timestamp: Time.current
    }
    
    Rails.logger.info "Benchmark #{name}: #{(duration * 1000).round(2)}ms, #{memory_delta.round(2)}MB"
    
    result
  end
  
  def log_slow_query(sql, duration)
    if duration > 0.1 # Log queries slower than 100ms
      @slow_queries << {
        sql: sql,
        duration: duration,
        timestamp: Time.current
      }
      
      Rails.logger.warn "Slow query (#{(duration * 1000).round(2)}ms): #{sql.truncate(200)}"
    end
  end
  
  def track_memory_usage(label = nil)
    usage = memory_usage_mb
    @memory_usage << {
      usage: usage,
      label: label,
      timestamp: Time.current
    }
    
    Rails.logger.info "Memory usage #{label ? "(#{label})" : ""}: #{usage.round(2)}MB"
  end
  
  def generate_report
    report = {
      timestamp: Time.current,
      benchmarks: format_benchmark_data,
      slow_queries: @slow_queries.last(10),
      memory_usage: @memory_usage.last(20),
      summary: generate_summary
    }
    
    Rails.logger.info "Performance Report Generated"
    Rails.logger.info JSON.pretty_generate(report)
    
    report
  end
  
  private
  
  def memory_usage_mb
    `ps -o pid,rss -p #{Process.pid}`.split("\n")[1].split[1].to_f / 1024
  rescue
    0.0
  end
  
  def format_benchmark_data
    @metrics.map do |name, measurements|
      recent_measurements = measurements.last(10)
      
      {
        name: name,
        count: measurements.size,
        avg_duration_ms: (recent_measurements.sum { |m| m[:duration] } / recent_measurements.size * 1000).round(2),
        max_duration_ms: (recent_measurements.max_by { |m| m[:duration] }[:duration] * 1000).round(2),
        avg_memory_delta_mb: (recent_measurements.sum { |m| m[:memory_delta] } / recent_measurements.size).round(2),
        last_run: recent_measurements.last[:timestamp]
      }
    end
  end
  
  def generate_summary
    total_benchmarks = @metrics.values.flatten.size
    total_slow_queries = @slow_queries.size
    current_memory = memory_usage_mb
    
    {
      total_benchmarks: total_benchmarks,
      total_slow_queries: total_slow_queries,
      current_memory_mb: current_memory.round(2),
      performance_grade: calculate_performance_grade
    }
  end
  
  def calculate_performance_grade
    # Simple performance grading based on metrics
    slow_query_ratio = @slow_queries.size.to_f / [@metrics.values.flatten.size, 1].max
    current_memory = memory_usage_mb
    
    case
    when slow_query_ratio > 0.1 || current_memory > 512
      'Poor'
    when slow_query_ratio > 0.05 || current_memory > 256
      'Fair'
    when slow_query_ratio > 0.01 || current_memory > 128
      'Good'
    else
      'Excellent'
    end
  end
end

# ActiveRecord query logging
if defined?(ActiveRecord)
  ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    # Skip schema queries and very fast queries
    unless event.payload[:name]&.match?(/SCHEMA|EXPLAIN/) || event.duration < 10
      PerformanceMonitor.log_slow_query(
        event.payload[:sql],
        event.duration / 1000.0
      )
    end
  end
end
EOF < /dev/null