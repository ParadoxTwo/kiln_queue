class MembersController < ApplicationController
  def index
    @members = Member.order(:name)
  end

  def show
    @member = Member.find(params[:id])
    @pieces = @member.pieces.order(created_at: :desc)
  end
end
