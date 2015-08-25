require 'digest/md5'
require 'time'

######################
#
## HTTP Cache Invalidation System
#
# The following cache validation system allows for the automatic caching of resources
# using a small DSL that can be enabled by including the LinkedData::HTTPCache::CacheableResource
# module into a class. See ontology_submission.rb for an example of complex usage.
#
# This isn't an actual cache. It just stores the last-modified times for objects in several
# different ways to allow for very efficient cache validation.
#
# CacheableResource objects must be used in conjunction with methods from the HTTPCacheHelper.
# The HTTPCacheHelper wraps Sinatra-based HTTP caching methods. The methods from HTTPCacheHelper
# should be used in Sinatra routes, as close to the beginning of the route as possible.
#
# If you include the LinkedData::HTTPCache::CacheableResource module for a class and use the
# HTTPCacheHelper methods, the resource will automatically cache for 60 seconds (default).
# You can use the DSL methods to configure more advanced cache invalidation approaches as
# described below.
#
#
# The simplest DSL method is for changing the default cache timeout:
#   class User
#     cache_timeout 8600 # makes the resource cache for an hour
#   end
#
# You can also give hints to the LinkedData::Models::Base#goo_attrs_to_load method about
# attributes that are required for determining whether or not the cache is valid.
# These attributes will be automatically loaded as a part of the goo_attrs_to_load invocation.
#  class Class
#    cache_load submission: [ontology: [:acronym]] # load ontology submission acronyms for class for cache validation
#  end
#
# The `cache_key` is a hash on an object's id attribute by default. This can be overridden
# using the `cache_key` method as follows:
# class MyClass
#   attr :my_id
#   cache_key lambda {|my_instance| Digest::MD5.hexdigest(my_instance.my_id)}
# end
#
### Cache Architecture
#
# The cache exists on a few levels. The first is a single resource.
# This is used when a request is for a particular resource, for example:
#   GET http://data.bioontology.org/ontologies/SNOMEDCT
#
# The cache key in this case would be the hash of the URL (which matches the ontology's id).
# However, the cache system also contains a record of last-modified times for
# ontologies as a whole, IE the last time ANY ontology was changed. This is referred
# to as a `collection`.
#
#### Collections
#
# The `collection` level information is used for calls like 'get all ontologies' and allows
# for a quick check to see if the client has stale data based on the last time ANY ontology
# was modified.
#
# A resource's `collection` is detected automatically using the Ruby class name, for example:
# LinkedData::Models::Ontology.
#
#### Segments
#
# There are also `segments`, which are last-modified times for sub-groups of related resources.
# For example, the Class model has a direct relationship to an Ontology model. If a single Class
# from an ontology is modified, it is safe to assume that all the other Classes related to that
# Ontology may also have changed. We want to invalidate the Classes associated with that Ontology
# only to avoid having to invalidate ALL Class resources. The `segment` allows us to do this.
#
# To configure a `segment` relationship, you can add the following to a class:
#   class OntologySubmission
#     cache_segment_instance lambda {|sub| segment_instance(sub)}
#     cache_segment_keys [:ontology_submission]
#
#     def self.segment_instance(sub)
#       sub.bring(:ontology) unless sub.loaded_attributes.include?(:ontology)
#       sub.ontology.bring(:acronym) unless sub.ontology.loaded_attributes.include?(:acronym)
#       [sub.ontology.acronym] rescue []
#     end
#   end
#
# The `cache_segment_instance` method takes a lambda that gets the id of the related resource.
# In the example above, the resource is an OntologySubmission whose instances are each
# related to a particular Ontology. This will be called when checking cache validity.
#
# The lambda will always pass in the instance of the object and that can be used to look
# up the id of the related resource. It should be returned in a list (even if it only has
# one member). Multiple items in the list will be concatenated when the segment portion
# of the cache key is generated.
#
# The `cache_segment_keys` are used in combination with the `cache_segment_instance`.
#
# The cache key that gets generated looks like this:
# httpcache:last_modified:segment:SNOMEDCT:ontology_submission

module LinkedData::HTTPCache
  class CacheableResourceRequirementsError < StandardError; end

  def self.invalidate_all
    key_set = LinkedData::HTTPCache::CacheableResource::KEY_SET
    keys = keys_for_invalidate_all()
    if keys
      keys.each_slice(500_000) {|chunk| redis.del chunk}
      redis.del key_set
    end
  end

  def self.keys_for_invalidate_all
    redis.smembers(LinkedData::HTTPCache::CacheableResource::KEY_SET)
  end

  def self.redis
    @redis ||= Redis.new(host: LinkedData.settings.http_redis_host,
                         port: LinkedData.settings.http_redis_port)
    @redis
  end

  module CacheableResource
    KEY_SET = "httpcache:keys"
    KEY_PREFIX = "httpcache:last_modified"
    SEGMENT_KEY_PREFIX = "httpcache:last_modified:segment"
    COLLECTION_KEY_PREFIX = "httpcache:last_modified:collection"

    ##
    # Compare a last modified string to the last modified time for this object
    def last_modified_valid?(last_modified)
      cache_read.eql?(last_modified)
    end

    ##
    # Invalidate the cache entry for this object
    def cache_invalidate
      LinkedData::HTTPCache.redis.hdel cache_prefix_and_segment, cache_key
      cache_segment_invalidate
      self.class.cache_collection_invalidate
    end

    ##
    # Invalidate all entries in the segment to which this object belongs
    def cache_segment_invalidate
      LinkedData::HTTPCache.redis.del cache_prefix_and_segment unless cache_segment.empty?
    end

    ##
    # The last modified time for this segment
    def segment_last_modified
      (LinkedData::HTTPCache.redis.hmget self.class.segment_key_prefix, cache_segment).first
    end

    ##
    # Update the last modified date in the cache for this object
    def cache_write
      time = Time.now.httpdate
      LinkedData::HTTPCache.redis.hmset cache_prefix_and_segment, cache_key, time
      LinkedData::HTTPCache.redis.hmset self.class.segment_key_prefix, cache_segment, time
      LinkedData::HTTPCache.redis.sadd self.class.key_set, cache_prefix_and_segment
      LinkedData::HTTPCache.redis.sadd self.class.key_set, self.class.segment_key_prefix
      self.class.cache_collection_write
      time
    end

    ##
    # The last modified time for this object
    def cache_read
      (LinkedData::HTTPCache.redis.hmget(cache_prefix_and_segment, cache_key) || []).first
    end
    alias :last_modified :cache_read

    ##
    # The cache key for this object
    def cache_key
      if self.class.cache_settings[:cache_key].first
        self.class.cache_settings[:cache_key].first.call(self)
      else
        Digest::MD5.hexdigest(self.id)
      end
    end

    ##
    # The cache key and the segment for the current object
    def cache_prefix_and_segment
      self.class.key_prefix + cache_segment
    end

    ##
    # The object's current segment
    def cache_segment
      segment = self.class.cache_settings[:cache_segment_keys] || []
      instance_prefix = (self.class.cache_settings[:cache_segment_instance] || []).first
      if instance_prefix.is_a?(Proc)
        segment_prefix = instance_prefix.call(self)
      elsif !segment.empty? && !instance_prefix.is_a?(Proc)
        raise CacheableResourceRequirementsError.new("You need to provide a `cache_segment_instance` lambda/proc when using cache segments")
      end
      segment = (segment_prefix || []) + segment
      return "" if segment.nil? || segment.empty?
      ":#{segment.join(':')}"
    end

    module ClassMethods
      ##
      # Wrappers for constants so they are available in instance
      def key_set() KEY_SET end
      def key_prefix() KEY_PREFIX end
      def segment_key_prefix() SEGMENT_KEY_PREFIX end

      ##
      # Update the collection last modified date
      def cache_collection_write
        time = Time.now.httpdate
        LinkedData::HTTPCache.redis.hmset cache_collection_prefix, cache_collection_key, time
        LinkedData::HTTPCache.redis.sadd KEY_SET, cache_collection_prefix
        time
      end

      ##
      # Get the collection last modified date
      def cache_collection_read
        (LinkedData::HTTPCache.redis.hmget(cache_collection_prefix, cache_collection_key) || []).first
      end
      alias :collection_last_modified :cache_collection_read

      ##
      # Compare a last modified string to the last modified time for this collection
      def collection_last_modified_valid?(last_modified)
        cache_collection_read.eql?(last_modified)
      end

      ##
      # Invalidate the cache entry for this collection
      def cache_collection_invalidate
        LinkedData::HTTPCache.redis.hdel cache_collection_prefix, cache_collection_key
      end

      ##
      # The cache key for this collection
      def cache_collection_key
        name
      end

      ##
      # The prefix for this collection
      def cache_collection_prefix
        COLLECTION_KEY_PREFIX
      end

      ##
      # Generate a segment for a class type with a given prefix
      def cache_segment(segment_prefix)
        segment = cache_settings[:cache_segment_keys] || []
        segment = segment_prefix + segment
        return "" if segment.nil? || segment.empty?
        ":#{segment.join(':')}"
      end

      ##
      # Add a new last modified for this segment
      def cache_segment_write(segment)
        LinkedData::HTTPCache.redis.hmset SEGMENT_KEY_PREFIX, segment, Time.now.httpdate
        LinkedData::HTTPCache.redis.sadd KEY_SET, SEGMENT_KEY_PREFIX
        cache_collection_write
      end

      ##
      # The last modified time for this segment
      def cache_segment_read(segment)
        (LinkedData::HTTPCache.redis.hmget SEGMENT_KEY_PREFIX, segment).first
      end
      alias :segment_last_modified :cache_segment_read

      ##
      # Timeout (default or set via cache_timeout)
      def max_age
        cache_settings[:cache_timeout].first || 60
      end
    end

    # Internal

    def self.included(base)
      base.extend(ClassMethods)
    end

    def self.store_settings(cls, type, setting)
      cls.cache_settings ||= {}
      cls.cache_settings[type] = setting
    end

    module ClassMethods
      attr_accessor :cache_settings

      # Methods with these names will be created
      # for each entry, allowing values to be
      # stored on a per-class basis
      SETTINGS = [
        :cache_key,
        :cache_timeout,
        :cache_segment_keys,
        :cache_segment_instance,
        :cache_load
      ]

      ##
      # Write methods on the class based on settings names
      SETTINGS.each do |method_name|
        define_method method_name do |*args|
          CacheableResource.store_settings(self, method_name, args)
        end
      end

      ##
      # Gets called by each class that inherits from this module
      # or classes that include this module
      def inherited(cls)
        super(cls)
        SETTINGS.each do |type|
          CacheableResource.store_settings(cls, type, [])
        end
      end
    end
  end
end
