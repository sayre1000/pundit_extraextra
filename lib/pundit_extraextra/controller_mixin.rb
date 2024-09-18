module PunditExtraExtra
  def self.included(_base)
    return unless defined? ActionController::Base

    ActionController::Base.class_eval do
      include PunditExtraExtra::Helpers
      include PunditExtraExtra::ResourceAutoload
    end
  end
end
