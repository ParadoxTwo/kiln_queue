class ReportsController < ApplicationController
  def monthly_statement
    member = Member.find(params.expect(:member_id))
    month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : Date.current
    render plain: Reports::MonthlyStatement.new(member.id, month).to_s
  rescue Date::Error
    render plain: "month must look like 2026-09", status: :bad_request
  end
end
