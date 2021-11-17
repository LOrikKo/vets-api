# frozen_string_literal: true

require 'evss/gi_bill_status/service'

class SavedClaim::EducationBenefits::VA10203 < SavedClaim::EducationBenefits
  include SentryLogging
  add_form_and_validation('22-10203')

  class Submit10203EVSSError < StandardError
  end

  def after_submit(user)
    @user = user
    if @user.present?
      @gi_bill_status = get_gi_bill_status
      create_stem_automated_decision
    end

    email_sent(false)
    return unless FeatureFlipper.send_email?

    StemApplicantConfirmationMailer.build(self, nil).deliver_now

    if @user.present?
      education_benefits_claim.education_stem_automated_decision.update(confirmation_email_sent_at: Time.zone.now)
      authorized = @user.authorize(:evss, :access?)

      if authorized
        EducationForm::SendSchoolCertifyingOfficialsEmail.perform_async(id, less_than_six_months?,
                                                                        get_facility_code)
      end
    end
  end

  def create_stem_automated_decision
    logger.info "EDIPI available for submit STEM claim id=#{education_benefits_claim.id}: #{@user.edipi.present?}"

    education_benefits_claim.build_education_stem_automated_decision(
      user_uuid: @user.uuid,
      auth_headers_json: EVSS::AuthHeaders.new(@user).to_h.to_json,
      poa: get_user_poa,
      remaining_entitlement: remaining_entitlement
    ).save
  end

  def email_sent(sco_email_sent)
    update_form('scoEmailSent', sco_email_sent)
    save
  end

  def get_user_poa
    # stem_automated_decision feature disables EVSS call  for POA which will be removed in a future PR
    return nil if Flipper.enabled?(:stem_automated_decision, @user)

    @user.power_of_attorney.present? ? true : nil
  rescue => e
    log_exception_to_sentry(Submit10203EVSSError.new("Failed to retrieve VSOSearch data: #{e.message}"))
    nil
  end

  private

  def get_gi_bill_status
    service = EVSS::GiBillStatus::Service.new(@user)
    service.get_gi_bill_status
  rescue => e
    Rails.logger.error "Failed to retrieve GiBillStatus data: #{e.message}"
    {}
  end

  def get_facility_code
    return {} if @gi_bill_status == {} || @gi_bill_status.enrollments.blank?

    most_recent = @gi_bill_status.enrollments.max_by(&:begin_date)

    return {} if most_recent.blank?

    most_recent.facility_code
  end

  def remaining_entitlement
    return nil if @gi_bill_status == {} || @gi_bill_status.remaining_entitlement.blank?

    months = @gi_bill_status.remaining_entitlement.months
    days = @gi_bill_status.remaining_entitlement.days

    ((months * 30) + days)
  end

  def less_than_six_months?
    return false if remaining_entitlement.blank?

    remaining_entitlement <= 180
  end
end
