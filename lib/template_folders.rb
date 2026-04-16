# frozen_string_literal: true

module TemplateFolders
  module_function

  Resolution = Struct.new(
    :folder,
    :authorization_folder,
    :requires_creation,
    :parent_name,
    :name,
    :parent_folder,
    keyword_init: true
  )

  def filter_by_full_name(template_folders, name)
    return template_folders.none if name.blank?

    parent_name, name = name.to_s.split(' / ', 2).map(&:squish)

    if name.present?
      parent_folder = template_folders.where(parent_folder_id: nil).find_by(name: parent_name)
    else
      name = parent_name
    end

    template_folders.where(name:, parent_folder:)
  end

  def search(folders, keyword)
    return folders if keyword.blank?

    sanitized = ActiveRecord::Base.sanitize_sql_like(keyword.downcase)

    folders.where(TemplateFolder.arel_table[:name].lower.matches("%#{sanitized}%"))
  end

  def filter_active_folders(template_folders, templates)
    return template_folders.none unless templates

    folder_exists =
      templates.active.where(TemplateFolder.arel_table[:id].eq(Template.arel_table[:folder_id]))
               .select(1).limit(1).arel.exists

    subfolders_arel = TemplateFolder.arel_table.alias('subfolders')

    subfolder_exists =
      TemplateFolder.from(subfolders_arel)
                    .where(subfolders_arel[:parent_folder_id].eq(TemplateFolder.arel_table[:id]))
                    .where(
                      templates.active.where(Template.arel_table[:folder_id].eq(subfolders_arel[:id])).arel.exists
                    ).select(1).limit(1).arel.exists

    template_folders.where(folder_exists).or(template_folders.where(subfolder_exists))
  end

  def sort(template_folders, current_account:, order:)
    case order
    when 'used_at'
      subquery =
        Template.left_joins(:submissions)
                .group(:folder_id)
                .where(account_id: current_account.id)
                .select(
                  :folder_id,
                  Template.arel_table[:updated_at].maximum.as('updated_at_max'),
                  Submission.arel_table[:created_at].maximum.as('submission_created_at_max')
                )

      template_folders = template_folders.joins(
        Template.arel_table
                .join(subquery.arel.as('templates'), Arel::Nodes::OuterJoin)
                .on(TemplateFolder.arel_table[:id].eq(Template.arel_table[:folder_id]))
                .join_sources
      )

      template_folders.order(
        Arel::Nodes::Case.new
                         .when(Template.arel_table[:submission_created_at_max].gt(Template.arel_table[:updated_at_max]))
                         .then(Template.arel_table[:submission_created_at_max])
                         .else(Template.arel_table[:updated_at_max])
                         .desc
      )
    when 'name'
      template_folders.order(name: :asc)
    else
      template_folders.order(id: :desc)
    end
  end

  def find_or_create_by_name(author, name)
    materialize_resolution(author, resolve_by_name(author.account, name))
  end

  def resolve_by_name(account, name, fallback_folder: nil)
    default_folder = fallback_folder || account.default_template_folder

    return Resolution.new(folder: default_folder, authorization_folder: default_folder, requires_creation: false) if name.blank? || name == TemplateFolder::DEFAULT_NAME

    parent_name, child_name = name.to_s.split(' / ', 2).map(&:squish)

    if child_name.present?
      parent_folder = account.template_folders.find_by(name: parent_name, parent_folder_id: nil)

      if parent_folder.present?
        folder = account.template_folders.find_by(name: child_name, parent_folder:)

        Resolution.new(
          folder:,
          authorization_folder: folder || parent_folder,
          requires_creation: folder.nil?,
          name: child_name,
          parent_name: parent_name,
          parent_folder:
        )
      else
        Resolution.new(
          folder: nil,
          authorization_folder: default_folder,
          requires_creation: true,
          name: child_name,
          parent_name:
        )
      end
    else
      folder = account.template_folders.find_by(name: parent_name, parent_folder_id: nil)

      Resolution.new(
        folder:,
        authorization_folder: folder || default_folder,
        requires_creation: folder.nil?,
        name: parent_name
      )
    end
  end

  def materialize_resolution(author, resolution)
    return resolution.folder if resolution.folder.present?
    return author.account.default_template_folder unless resolution.requires_creation

    if resolution.parent_name.present?
      parent_folder = resolution.parent_folder ||
                      author.account.template_folders.create_with(author:)
                            .find_or_create_by(name: resolution.parent_name, parent_folder_id: nil)

      author.account.template_folders.create_with(author:)
            .find_or_create_by(name: resolution.name, parent_folder:)
    else
      author.account.template_folders.create_with(author:)
            .find_or_create_by(name: resolution.name, parent_folder: nil)
    end
  end
end
