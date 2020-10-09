# frozen_string_literal: true

class ProfilePhotoAttachmentUploader < CarrierWave::Uploader::Base
  PROCESSING_CLASS = VIC::ProcessingUploader
  include ValidateFileSize
  include SetAwsConfig
  include AsyncProcessing
  include LogMetrics

  MAX_FILE_SIZE = 10.megabytes

  def initialize(guid)
    super
    @guid = guid

    if Rails.env.production?
      set_aws_config(
        Settings.vic.s3.aws_access_key_id,
        Settings.vic.s3.aws_secret_access_key,
        Settings.vic.s3.region,
        Settings.vic.s3.bucket
      )
    end
  end

  def extension_whitelist
    %w[jpg jpeg gif png tif tiff]
  end

  def filename
    @guid
  end

  def store_dir
    'profile_photo_attachments'
  end
end
