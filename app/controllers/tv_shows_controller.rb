require 'open-uri'
class TvShowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_last_seen_at, if: proc { current_user && (current_user.last_seen_at.nil? || current_user.last_seen_at < 15.minutes.ago) }

  def index
    user = current_user
    sort = params[:sort].in?(['titlea', 'titled']) ? params[:sort] : nil
    filter = params[:filter].in?(['all', 'new']) ? params[:filter] : nil

    unviewed_queued_episode_ids = user.queued_episodes.joins(:episode).where("viewed = false AND episodes.airdate < ?", Time.now).pluck(:episode_id)
    @shows_with_new_episodes_ids = Episode.where(:id => unviewed_queued_episode_ids).pluck(:tv_show_id).uniq
    if filter == "new"
      @full_show_list = TvShow.for_user(user).where(id: @shows_with_new_episodes_ids).order(show_sort(sort))
    else
      @full_show_list = TvShow.for_user(user).order(show_sort(sort))
    end
    @full_show_list.each do |show|
      show.add_or_update
      show.add_or_update_network
    end

  end

  def show
    @user = current_user
    # Clean this up: no need for duplicate variables
    @tv_show_id = tv_show_id = show_or_remove_tv_show_params[:tv_show_id]
    tv_show = TvShow.find(tv_show_id)
    sort = params[:sort].in?(['showa', 'showd', 'datea', 'dated']) ? params[:sort] : nil
    filter = params[:filter].in?(['all', 'new']) ? params[:filter] : nil
    tv_show.add_or_update
    tv_show.add_or_update_episodes
    @partial_queue = (filter == 'new') ? @user.queued_episodes.joins(:episode).where("episodes.tv_show_id = ? AND queued_episodes.viewed = ?", tv_show_id, episode_filter(filter)).order(episode_sort(sort)) : @user.queued_episodes.joins(:episode).where("episodes.tv_show_id = ?", tv_show_id).order(episode_sort(sort))
    @next_episode = @partial_queue.where(viewed: false).last || @partial_queue.first
  end

  def search

  end

  def search_results
    @search_string = search_query_params
    @potential_show_data = search_for_show(@search_string)
    user_tv_show_ids = current_user.episodes.joins(:tv_show).map(&:tv_show_id).uniq
    @user_tv_show_tmdb_ids = TvShow.where(id: user_tv_show_ids).pluck(:tmdb_id)
  end

  def add
    show_to_add = add_tv_show_params
    tv_show = TvShow.find_or_initialize_by(tmdb_id: show_to_add[:tmdb_id])
    tv_show.add_or_update
    tv_show.add_or_update_network
    tv_show = TvShow.find_by(tmdb_id: show_to_add[:tmdb_id])
    tv_show.add_or_update_episodes
    tv_show.queue_episodes(current_user)

    respond_to do |format|
      format.html { redirect_to '/tv_shows/index' }
      format.js { redirect_to '/tv_shows/index' }
    end
  end

  def remove
    tv_show_to_remove = show_or_remove_tv_show_params[:tv_show_id]
    tv_show = TvShow.find_by(id: tv_show_to_remove)
    episode_ids_to_dequeue = Episode.where(tv_show: tv_show).map(&:id)
    queued_episodes_to_remove = QueuedEpisode.where(user: current_user, episode_id: episode_ids_to_dequeue)
    queued_episodes_to_remove.delete_all

    respond_to do |format|
      format.html { redirect_to root_url }
      format.js { render 'tv_shows/update_tv_shows_index' }
    end
  end

  def mass_mark_viewed
    tmdb_id = mass_mark_viewed_params[1]
    season, episode = mass_mark_viewed_params[0][:season], mass_mark_viewed_params[0][:episode]
    current_season = season.to_i.abs
    last_episode = episode.to_i.abs

    episodes = TvShow.find_by(tmdb_id: tmdb_id).episodes.all

    episodes.each do |e|
      if e.season < current_season
        watched = QueuedEpisode.find_by(user: current_user, episode: e)
        watched.viewed = true
        watched.save
      elsif e.season == current_season && e.episode_number <= last_episode
        watched = QueuedEpisode.find_by(user: current_user, episode: e)
        watched.viewed = true
        watched.save
      end
    end

    respond_to do |format|
      format.html { redirect_to root_url }
      format.js
    end
  end

  private

  def episode_filter(method)
    case method
    when 'new' then
      return 'false'
    end
  end

  def show_sort(method)
    case method
    when 'titlea' then
      return 'title asc'
    when 'titled' then
      return 'title desc'
    end
  end

  def episode_sort(method)
    case method
    when 'showa' then
      return 'episodes.title asc'
    when 'showd' then
      return 'episodes.title desc'
    when 'datea' then
      return 'episodes.airdate asc'
    when 'dated' then
      return 'episodes.airdate desc'
    else
      return 'episodes.airdate desc, episodes.season desc, episodes.episode_number desc'
    end
  end

  def search_for_show(query_string)
    potential_show_data = []
    response = open("https://api.themoviedb.org/3/search/tv?api_key=#{ENV['TMDB_API_KEY']}&language=en-US&query=#{URI.escape(query_string)}").read
    potential_shows = JSON.parse(response)

    potential_shows["results"].each do |r|
      potential_show_data << {tmdb_id: r["id"], poster_path: r["poster_path"], first_air_date: r["first_air_date"], title: r["name"]}
    end
    return potential_show_data
  end

  def search_query_params
    params.require(:search_query)
  end

  def add_tv_show_params
    params.permit(:first_air_date, :poster_path, :title, :tmdb_id)
  end

  def tv_show_params
    params.require(:tv_show).permit(:query_string)
  end

  def mass_mark_viewed_params
    params.require([:show, :tmdb_id])
  end

  def show_or_remove_tv_show_params
    params.permit(:tv_show_id)
  end

end
