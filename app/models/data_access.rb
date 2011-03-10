require 'BioPortalRestfulCore'
require "digest/sha1"
include Spawn

class DataAccess
  # Sets what backend we are using
  SERVICE = BioPortalRestfulCore
  
  # Last multiplicand is number of hours 
  CACHE_EXPIRE_TIME = 60*60*4
  SHORT_CACHE_EXPIRE_TIME = 60*60*1
  MEDIUM_CACHE_EXPIRE_TIME = 60*60*12
  LONG_CACHE_EXPIRE_TIME = 60*60*24
  EXTENDED_CACHE_EXPIRE_TIME = 60*60*336 # two weeks

  NO_CACHE = false
  
  def self.getNode(ontology_id, node_id, view = false)
    view_string = view ? "view_" : ""
    return self.cache_pull("#{view_string}#{param(ontology_id)}::#{node_id.to_s.gsub(" ","%20")}", "getNode", { :ontology_id => ontology_id, :concept_id => node_id })
  end

  def self.getLightNode(ontology_id, node_id, view = false)
    view_string = view ? "view_" : ""
    return self.cache_pull("#{view_string}#{param(ontology_id)}::#{node_id.to_s.gsub(" ","%20")}_light", "getLightNode", { :ontology_id => ontology_id, :concept_id => node_id })
  end
  
  def self.getView(view_id)
    return self.cache_pull("view::#{param(view_id)}", "getView", { :view_id => view_id })
  end

  def self.getViewList
    return self.cache_pull("view_list", "getViewList", nil, MEDIUM_CACHE_EXPIRE_TIME)
  end

  def self.getViews(ontology_id)
    return self.cache_pull("views::#{param(ontology_id)}", "getViews", { :ontology_id => ontology_id })
  end
  
  def self.getTopLevelNodes(ontology_id, view = false)
    view_string = view ? "view_" : ""
    return self.cache_pull("#{view_string}#{param(ontology_id)}::_top", "getTopLevelNodes", { :ontology_id => ontology_id, :view => view })
  end
  
  def self.getOntologyList
    ontologies = self.cache_pull("ont_list", "getOntologyList", nil, MEDIUM_CACHE_EXPIRE_TIME)
    
    # Create an array of ontology accronyms to avoid duplicate entries
    # Get a total of all terms for ontologies
    if CACHE.get("ontology_acronyms").nil?
      ontology_acronyms = []
      ontologies.each do |ontology|
        ontology_acronyms << ontology.abbreviation.downcase
      end
      CACHE.set("ontology_acronyms", ontology_acronyms, MEDIUM_CACHE_EXPIRE_TIME)
    end
    
    return ontologies
  end
  
  def self.getTotalTermCount
    ontologies = self.getOntologyList
    
    terms = CACHE.get("terms_all_ontologies")
    running = CACHE.get("running_term_calc")
    
    if (CACHE.get("terms_all_ontologies").nil? || CACHE.get("terms_all_ontologies").to_i <= 0) && (CACHE.get("running_term_calc").nil? || !CACHE.get("running_term_calc").eql?("true"))
      CACHE.set("running_term_calc", "true", 60*15)
      
      # Set a default term count, based on a value from Feb 2011
      CACHE.set("terms_all_ontologies", 4849100)
      
      # Spawn a process to calculate total term size
      spawn(:argv => "spawn_ontology_terms") do
        total_terms = 0
        ontologies.each do |ontology|
          total_terms += self.getOntologyMetrics(ontology.id).numberOfClasses.to_i rescue 0
        end

        # Since we spawn a new process we need to make sure to reset the cache
        CACHE.reset

        CACHE.set("terms_all_ontologies", total_terms, MEDIUM_CACHE_EXPIRE_TIME)
        CACHE.set("running_term_calc", "false")
        
        # Since we spawn a new process we need to make sure to reset the cache
        CACHE.reset
      end
    end

    CACHE.reset
    return CACHE.get("terms_all_ontologies")
  end
  
  def self.getCategories
    return self.cache_pull("categories", "getCategories", nil, EXTENDED_CACHE_EXPIRE_TIME)
  end
  
  def self.getGroups
    return self.cache_pull("groups", "getGroups", nil, EXTENDED_CACHE_EXPIRE_TIME)
  end
  
  def self.getActiveOntologies
    return self.cache_pull("act_ont_list", "getActiveOntologyList", nil, MEDIUM_CACHE_EXPIRE_TIME)
  end
  
  def self.getOntologyVersions(ontology_virtual_id)
    return self.cache_pull("#{ontology_virtual_id}::_versions", "getOntologyVersions", { :ontology_virtual_id => ontology_virtual_id })
  end
  
  def self.getOntology(ontology_id)
    return self.getLatestOntology(ontology_id) if ontology_id.to_i < 10000
    return self.cache_pull("#{ontology_id}::_details", "getOntology", { :ontology_id => ontology_id })
  end
  
  def self.getLatestOntology(ontology_virtual_id)
    return self.cache_pull("#{ontology_virtual_id}::_latest", "getLatestOntology", { :ontology_virtual_id => ontology_virtual_id })
  end

  def self.getOntologyMetrics(ontology_id)
    metrics = self.cache_pull("#{ontology_id}::_metrics", "getOntologyMetrics", { :ontology_id => ontology_id })
    
    # Check to see if there were valid metrics returned, else get older version 
    if metrics.nil? || metrics.numberOfClasses.to_i <= 0
      versions = self.getOntologyVersions(self.getOntology(ontology_id).ontologyId)
      versions.sort! { |x, y| x.id <=> y.id }
      versions.reverse!
      versions.each_with_index do |version, index|
        if version.id.eql?(ontology_id)
          next
        end
        metrics_old = self.cache_pull("#{version.id}::_metrics", "getOntologyMetrics", { :ontology_id => version.id })
        if !metrics_old.nil? && metrics_old.numberOfClasses.to_i > 0
          return metrics_old
        elsif index >= 20 # 21 most recent versions are checked (3 weeks)
          return nil
        end
      end
    end
    
    return metrics
  end

  def self.getNote(ontology_id, note_id, threaded = false, virtual = false)
    threaded_token = threaded ? "::threaded" : ""
    return self.cache_pull("#{note_id}#{threaded_token}", "getNote", { :ontology_id => ontology_id, :note_id => note_id, :threaded => threaded, :virtual => virtual }, EXTENDED_CACHE_EXPIRE_TIME)
  end
  
  def self.getNotesForConcept(ontology_id, concept_id, threaded = false, virtual = false)
    return self.cache_pull("#{concept_id}::notes", "getNotesForConcept", { :ontology_id => ontology_id, :concept_id => concept_id, :threaded => threaded, :virtual => virtual }, 60*15)
  end
  
  def self.getNotesForIndividual(ontology_virtual_id, individual_id, threaded = false)
    return self.cache_pull("#{individual_id}::notes", "getNotesForIndividual", { :ontology_virtual_id => ontology_virtual_id, :individual_id => individual_id, :threaded => threaded }, 60*15)
  end
  
  def self.getNotesForOntology(ontology_virtual_id, threaded = false, virtual = false)
    return self.cache_pull("#{ontology_virtual_id}::notes", "getNotesForOntology", { :ontology_virtual_id => ontology_virtual_id, :threaded => threaded, :virtual => virtual }, 60*15)
  end
  
  def self.updateNote(ontology_id, params, virtual = false)
    note = SERVICE.updateNote(ontology_id, params, virtual)
    CACHE.set("#{note.id}", note, CACHE_EXPIRE_TIME)
    CACHE.delete("#{params[:appliesTo]}::notes") if params[:appliesToType].eql?("Class")
    CACHE.delete("#{ontology_id}::notes")
    note
  end
  
  def self.createNote(params)
    note = SERVICE.createNote(params)
    CACHE.set("#{note.id}", note, CACHE_EXPIRE_TIME)
    CACHE.delete("#{params[:appliesTo]}::notes") if params[:appliesToType].eql?("Class")
    CACHE.delete("#{params[:ontology_virtual_id]}::notes")
    
    # If this note is in a thread, traverse to top and delete from cache
    if params[:appliesToType].eql?("Note")
      note_temp = self.getNote(params[:ontology_virtual_id], params[:appliesTo], false, true)
      while note_temp.appliesTo['type'].eql?("Note")
        old_note_id = note_temp.id
        parent_note_id = self.getNote(params[:ontology_virtual_id], note_temp.id, false, true).appliesTo['id']
        CACHE.delete("#{old_note_id}")
        CACHE.delete("#{old_note_id}::threaded")
        note_temp = self.getNote(params[:ontology_virtual_id], parent_note_id, false, true)
      end
      CACHE.delete("#{note_temp.id}::threaded")
      CACHE.delete("#{note_temp.id}")
    end

    # If this note applies to a class/concept/term then delete the count for that concept
    CACHE.delete("#{params[:ontology_virtual_id]}::#{params[:appliesTo]}_NoteCount") if params[:appliesToType].eql?("Class")
    
    # Remove cached notes for this ontology
    CACHE.delete("#{params[:ontology_virtual_id]}::notes")
    
    # We rescue all so the user doesn't get an error if the add fails
    begin
      # Add note to index table
      notes_index = NotesIndex.new
      notes_index.populate(note)
      notes_index.save
      
      # Adds note to syndication
      event = EventItem.new
      event.event_type = "Note"
      event.event_type_id = note.id
      event.ontology_id = params[:ontology_virtual_id]
      event.save
    rescue Exception => e
    end

    note
  end
  
  def self.archiveNote(params)
    note = SERVICE.archiveNote(params)
    CACHE.set("#{note.id}", note, CACHE_EXPIRE_TIME)
    CACHE.set("#{note.id}::threaded", note)
    CACHE.delete("#{params[:appliesTo]}::notes") if params[:appliesToType].eql?("Class")
    CACHE.delete("#{params[:ontology_virtual_id]}::notes")
    
    # If this note is in a thread, traverse to top and delete from cache
    if params[:appliesToType].eql?("Note")
      note_temp = self.getNote(params[:ontology_virtual_id], params[:appliesTo], false, true)
      while note_temp.appliesTo['type'].eql?("Note")
        old_note_id = note_temp.id
        parent_note_id = self.getNote(params[:ontology_virtual_id], note_temp.id, false, true).appliesTo['id']
        CACHE.delete("#{old_note_id}")
        CACHE.delete("#{old_note_id}::threaded")
        note_temp = self.getNote(params[:ontology_virtual_id], parent_note_id, false, true)
      end
      CACHE.delete("#{note_temp.id}::threaded")
      CACHE.delete("#{note_temp.id}")
    end

    # If this note applies to a class/concept/term then delete the count for that concept
    CACHE.delete("#{params[:ontology_virtual_id]}::#{params[:appliesTo]}_NoteCount") if params[:appliesToType].eql?("Class")
    
    # Remove cached notes for this ontology
    CACHE.delete("#{params[:ontology_virtual_id]}::notes")
    
    note
  end
  
  def self.createMapping(source, source_ontology_id, target, target_ontology_id, user_id, comment, unidirectional)
    mapping = SERVICE.createMapping({ :source => source, :sourceontology => source_ontology_id, :target => target, :targetontology => target_ontology_id, :submittedby => user_id, :comment => comment, :unidirectional => unidirectional })
    
    CACHE.delete("ontoliges::map_count")
    CACHE.delete("ontoliges::users::map_count")
    CACHE.delete("between_ontoliges::map_count::#{source_ontology_id}")
    CACHE.delete("between_ontoliges::map_count::#{target_ontology_id}")
    CACHE.delete("#{source_ontology_id}::#{CGI.escape(source)}::map_count")
    CACHE.delete("#{target_ontology_id}::#{CGI.escape(target)}::map_count")
    CACHE.delete("#{source_ontology_id}::map_count")
    CACHE.delete("#{target_ontology_id}::map_count")
    CACHE.delete("recent::mappings")
    CACHE.delete("#{source_ontology_id}::#{CGI.escape(source)}::map_page::page1::size100::params")
    CACHE.delete("#{target_ontology_id}::#{CGI.escape(target)}::map_page::page1::size100::params")
    CACHE.delete("#{source_ontology_id}::concepts::map_count")
    CACHE.delete("#{target_ontology_id}::concepts::map_count")
    
    return mapping
  end
  
  def self.getMapping(mapping_id)
    self.cache_pull("#{mapping_id}::mapping", "getMapping", { :mapping_id => mapping_id }, LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getConceptMappings(ontology_virtual_id, concept_id, page_number = 1, page_size = 100, params = {})
    self.cache_pull("#{ontology_virtual_id}::#{CGI.escape(concept_id)}::map_page::page#{page_number}::size#{page_size}::params#{params.to_s}", "getConceptMappings", { :ontology_virtual_id => ontology_virtual_id, :concept_id => concept_id, :page_number => page_number, :page_size => page_size }.merge(params), LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getOntologyMappings(ontology_virtual_id, page_number = 1, page_size = 100, params = {})
    self.cache_pull("#{ontology_virtual_id}::map_page::page#{page_number}::size#{page_size}::params#{params.to_s}", "getOntologyMappings", { :ontology_virtual_id => ontology_virtual_id, :page_number => page_number, :page_size => page_size }.merge(params), LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getBetweenOntologiesMappings(source_ontology_virtual_id, target_ontology_virtual_id, page_number = 1, page_size = 100, params = {})
  	# We avoid caching this result when it might be too big (> 5000 results)
  	if page_size > 5000
  	  SERVICE.getBetweenOntologiesMappings({ :source_ontology_virtual_id => source_ontology_virtual_id, :target_ontology_virtual_id => target_ontology_virtual_id, :page_number => page_number, :page_size => page_size }.merge(params))
  	else
      self.cache_pull("#{source_ontology_virtual_id}::#{target_ontology_virtual_id}::map_page::page#{page_number}::size#{page_size}::params#{params.to_s}", "getBetweenOntologiesMappings", { :source_ontology_virtual_id => source_ontology_virtual_id, :target_ontology_virtual_id => target_ontology_virtual_id, :page_number => page_number, :page_size => page_size }.merge(params), LONG_CACHE_EXPIRE_TIME)
	end
  end
  
  def self.getMappingCountOntology(ontology_virtual_id)
    self.cache_pull("#{ontology_virtual_id}::map_count", "getMappingCountOntology", { :ontology_virtual_id => ontology_virtual_id }, LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getMappingCountConcept(ontology_virtual_id, concept_id)
    self.cache_pull("#{ontology_virtual_id}::#{CGI.escape(concept_id)}::map_count", "getMappingCountConcept", { :ontology_virtual_id => ontology_virtual_id, :concept_id => concept_id }, LONG_CACHE_EXPIRE_TIME)
  end

  def self.getMappingCountBetweenOntologies(ontology_virtual_id)
    self.cache_pull("between_ontoliges::map_count::#{ontology_virtual_id}", "getMappingCountBetweenOntologies", { :ontology_virtual_id => ontology_virtual_id }, LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getMappingCountOntologies
    self.cache_pull("ontoliges::map_count", "getMappingCountOntologies", nil, LONG_CACHE_EXPIRE_TIME)
  end

  def self.getMappingCountOntologyConcepts(ontology_virtual_id, limit = 35)
    self.cache_pull("#{ontology_virtual_id}::concepts::map_count", "getMappingCountOntologyConcepts", { :ontology_virtual_id => ontology_virtual_id, :limit => limit }, LONG_CACHE_EXPIRE_TIME)
  end

  def self.getMappingCountOntologyUsers(ontology_virtual_id)
    self.cache_pull("ontoliges::users::map_count", "getMappingCountOntologyUsers", { :ontology_virtual_id => ontology_virtual_id }, LONG_CACHE_EXPIRE_TIME)
  end

  def self.getRecentMappings
    self.cache_pull("recent::mappings", "getRecentMappings", nil, 60*15)
  end

  def self.getNodeNameContains(ontologies, search, page, params = {}) 
    results,pages = SERVICE.getNodeNameContains(ontologies, search, page, params)
    return results,pages
  end

  def self.getUsers
    return self.cache_pull("user_list", "getUsers", nil, LONG_CACHE_EXPIRE_TIME)
  end
  
  def self.getUserByEmail(email)
    found_user = nil
    users = self.getUsers
    for user in users
      if user.email.eql?(email)
        found_user = user
      end
    end
    return found_user              
  end
  
  def self.getUserByUsername(username)
    found_user = nil
    users = self.getUsers
    for user in users
      if user.username.eql?(username)
        found_user = user
      end
    end
    return found_user              
  end
  
  def self.getUser(user_id)
    return self.cache_pull("user::#{user_id}", "getUser", { :user_id => user_id })
  end
  
  def self.authenticateUser(username, password)    
    user = SERVICE.authenticateUser(username, password)
    return user
  end
  
  def self.createUser(params)    
    user = SERVICE.createUser(params)
    CACHE.delete("user_list")
    return user
  end
  
  def self.updateUser(params, user_id)
    user = SERVICE.updateUser(params, user_id)
    CACHE.delete("user_list")
    CACHE.delete("user::#{user_id}")
    return user
  end
  
  def self.createOntology(params)
    ontology = SERVICE.createOntology(params)
    CACHE.delete("act_ont_list")
    CACHE.delete("ont_list")
    unless(params[:ontologyId].nil?)
      CACHE.delete("#{params[:ontologyId]}::_versions")
      CACHE.delete("#{params[:ontologyId]}::_details")
      CACHE.delete("ont_list")
    end
    return ontology
  end
  
  def self.updateOntology(params, ontology_id)
    SERVICE.updateOntology(params, ontology_id)
    CACHE.delete("#{ontology_id}::_details")
    CACHE.delete("ont_list")
    unless(params[:ontologyId].nil?)
 	  CACHE.delete("#{params[:ontologyId]}::_latest")
      CACHE.delete("#{params[:ontologyId]}::_versions")
      CACHE.delete("#{params[:ontologyId]}::_details")
      CACHE.delete("ont_list")
    end
    return self.getOntology(ontology_id)
  end
  
  def self.updateView(params, ontology_id)
    SERVICE.updateOntology(params, ontology_id)
    CACHE.delete("view::#{ontology_id}")
    CACHE.delete("views::#{self.getOntology(params[:viewOnOntologyVersionId]).ontologyId}")
    return self.getLatestOntology(params[:ontologyId])
  end
  
  def self.download(ontology_id)
    return SERVICE.download(ontology_id)
  end
  
  def self.getPathToRoot(ontology_id, source)
    return self.cache_pull("#{param(ontology_id)}::#{source.gsub(" ","%20")}_path_to_root", "getPathToRoot", { :ontology_id => ontology_id, :concept_id => source })
  end
  
  def self.getDiffs(ontology_id)
    pairs = SERVICE.getDiffs(ontology_id)
    return pairs
  end
  
private

  def self.param(string)
    return string.to_s.gsub(" ","_")
  end
   
  def self.cache_pull(token, service_call, params = nil, expires = CACHE_EXPIRE_TIME)
    if NO_CACHE || CACHE.get(token).nil?
      if params
        retrieved_object = SERVICE.send(:"#{service_call}", params)
      else
        retrieved_object = SERVICE.send(:"#{service_call}")
      end
      
      unless retrieved_object.kind_of?(Hash) && retrieved_object[:error]
        CACHE.set(token, retrieved_object, expires)
      end
      
      return retrieved_object
    else
      return CACHE.get(token)
    end
  end
  
end
