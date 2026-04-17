# frozen_string_literal: true

class UploadSpreadsheetsController < ApplicationController
  require 'csv'
  require 'rubyXL'

  skip_authorization_check

  UnsupportedSpreadsheetFile = Class.new(StandardError)

  def create
    render json: parse_spreadsheet(uploaded_file)
  rescue UnsupportedSpreadsheetFile
    render json: { error: I18n.t('invalid_file_type') }, status: :unprocessable_content
  rescue CSV::MalformedCSVError, Zip::Error, ArgumentError
    render json: { error: I18n.t('unable_to_read_spreadsheet') }, status: :unprocessable_content
  end

  private

  def uploaded_file
    file = params[:file]

    raise UnsupportedSpreadsheetFile if file.blank?

    file
  end

  def parse_spreadsheet(file)
    extension = File.extname(file.original_filename.to_s).downcase

    spreadsheet =
      case extension
      when '.csv'
        [['Sheet1', compact_rows(CSV.parse(file.read, encoding: 'bom|utf-8'))]]
      when '.xlsx'
        workbook_to_json(RubyXL::Parser.parse_buffer(file.read))
      else
        raise UnsupportedSpreadsheetFile
      end

    raise ArgumentError if spreadsheet.blank? || spreadsheet.all? { |_, rows| rows.blank? }

    spreadsheet
  ensure
    file.rewind if file.respond_to?(:rewind)
  end

  def workbook_to_json(workbook)
    workbook.worksheets.filter_map do |worksheet|
      max_columns = worksheet.sheet_data&.rows.to_a.compact.map { |row| row.cells.size }.max.to_i
      rows = compact_rows(build_sheet_rows(worksheet, max_columns))

      next if rows.blank?

      [worksheet.sheet_name, rows]
    end
  end

  def build_sheet_rows(worksheet, max_columns)
    worksheet.sheet_data&.rows.to_a.map do |row|
      Array.new(max_columns) { |index| serialize_cell(row&.cells&.[](index)) }
    end || []
  end

  def compact_rows(rows)
    rows.reject { |row| Array.wrap(row).all? { |value| value.nil? || value == '' } }
  end

  def serialize_cell(cell)
    return if cell.nil?

    value = cell.value

    case value
    when Date, DateTime, Time
      value.iso8601
    else
      value
    end
  end
end
