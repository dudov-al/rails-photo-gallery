class Current < ActiveSupport::CurrentAttributes
  # Request-scoped attributes for security context
  
  attribute :photographer, :request_id, :request_ip, :user_agent, :session_id
  
  def self.set_request_context(request)
    self.request_ip = request.remote_ip
    self.user_agent = request.user_agent
    self.request_id = request.uuid
    self.session_id = request.session.id if request.session
  end
end