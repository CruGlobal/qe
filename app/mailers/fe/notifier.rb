module Fe
  class Notifier < ActionMailer::Base

    # call Notifier.deliver_notification
    def notification(p_recipients, p_from, template_name, template_params = {}, options = {})
      email_template = EmailTemplate.find_by_name(template_name)

      if email_template.nil?
        raise "Email Template '#{template_name}' could not be found"
      else
        set_format = options.delete(:format)
        mail({:to => p_recipients,
             :from => p_from,
             :subject => Liquid::Template.parse(email_template.subject).render(template_params)}.merge(options)) do |format|
          case set_format.to_s
          when 'html'
            format.html { render html: Liquid::Template.parse(email_template.content).render(template_params) }
          else
            format.text { render plain: Liquid::Template.parse(email_template.content).render(template_params) }
          end
        end
        @recipients = p_recipients
        @from = p_from
        @subject = Liquid::Template.parse(email_template.subject).render(template_params)
        @body = Liquid::Template.parse(email_template.content).render(template_params)
      end
    end
  end
end
