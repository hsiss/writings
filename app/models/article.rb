class Article
  include Mongoid::Document
  include Mongoid::Timestamps
  include ActiveModel::ForbiddenAttributesProtection

  field :title
  field :body
  field :urlname
  field :old_url
  field :status, :default => 'draft'
  field :save_count, :type => Integer, :default => 0
  field :last_version_save_count, :type => Integer, :default => 0
  field :published_at

  field :token
  index({ :space_id => 1, :token => 1 }, { :unique => true })
  index({ :space_id => 1, :old_url => 1 }, { :sparse => true })

  belongs_to :space
  belongs_to :category
  belongs_to :last_edit_user, :class_name => 'User'

  has_many :versions, :order => [:created_at, :desc]
  has_many :notes

  validates :urlname, :format => { :with => /\A[a-zA-Z0-9-]+\z/, :message => I18n.t('urlname_valid_message'), :allow_blank => true }

  scope :publish, -> { where(:status => 'publish') }
  scope :draft, -> { where(:status => 'draft') }
  scope :trash, -> { where(:status => 'trash') }

  scope :status, -> status {
    case status
    when 'publish'
      publish
    when 'draft'
      draft
    when 'trash'
      trash
    else
      where(:status.ne => 'trash')
    end
  }

  delegate :name, :urlname, :to => :category, :prefix => true, :allow_nil => true

  before_save :set_published_at

  def set_published_at
    if status_changed? && publish?
      self.published_at = Time.now.utc
    end
  end

  def create_version(options = {})
    user = options[:user] || self.space

    versions.create :title => title,
                    :body  => body,
                    :user  => user
    update_attribute :last_version_save_count, self.save_count
  end

  def publish?
    self.status == 'publish'
  end

  def draft?
    self.status == 'draft'
  end

  def trash?
    self.status == 'trash'
  end

  def title
    read_attribute(:title).blank? ? I18n.t(:untitled) : read_attribute(:title)
  end

  before_validation :set_token

  def set_token
    if new_record?
      self.token ||= space.inc(:article_next_id, 1).to_s
    end
  end

  def to_param
    self.token.to_s
  end

  def lock_by(user)
    Rails.cache.write "/articles/#{id}/locked_by", user.id, :expires_in => 10.seconds
  end

  def locked_by
    @locked_by = Rails.cache.read("/articles/#{id}/locked_by") if !defined?(@locked_by)
    @locked_by
  end

  def locked_by_user
    if locked_by
      User.where(:id => locked_by).first
    end
  end

  def locked?
    !!locked_by
  end

  def locked_by?(user)
    locked_by == user.id
  end
end
