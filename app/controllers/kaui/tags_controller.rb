class Kaui::TagsController < Kaui::EngineController

  def index
    @search_query = params[:q]

    @limit = 50
    if @search_query.blank?
      max_nb_records = Kaui::Tag.list_or_search(nil, 0, 0, options_for_klient).pagination_max_nb_records
      @offset = [0, max_nb_records - @limit].max
      @ordering = 'desc'
    else
      @offset = 0
      @ordering = 'asc'
    end
  end

  def pagination
    searcher = lambda do |search_key, offset, limit|
      Kaui::Tag.list_or_search(search_key, offset, limit, options_for_klient)
    end

    data_extractor = lambda do |tag, column|
      [
          tag.tag_id,
          tag.object_id,
          tag.object_type,
          tag.tag_definition_name
      ][column]
    end

    formatter = lambda do |tag|
      url_for_object = view_context.url_for_object(tag.object_id, tag.object_type)
      [
          tag.tag_id,
          url_for_object ? view_context.link_to(tag.object_id, url_for_object) : tag.object_id,
          tag.object_type,
          tag.tag_definition_name
      ]
    end

    paginate searcher, data_extractor, formatter
  end
end
