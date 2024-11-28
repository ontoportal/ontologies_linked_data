module LinkedData
  module Concerns
    module Concept
      module Tree
        def tree(concept_schemes: [], concept_collections: [], roots: nil)
          bring(parents: [:prefLabel]) if bring?(:parents)

          return self if parents.nil? || parents.empty?

          extra_include = [:hasChildren, :isInActiveScheme, :isInActiveCollection]

          roots = self.submission.roots(extra_include, concept_schemes: concept_schemes) if roots.nil?
          path = path_to_root(roots)
          threshold = 100

          return self if path.nil?

          attrs_to_load = %i[prefLabel synonym obsolete]
          attrs_to_load << :subClassOf if submission.hasOntologyLanguage.obo?
          attrs_to_load += self.class.concept_is_in_attributes if submission.skos?

          self.class.in(submission)
              .models(path)
              .include(attrs_to_load).all

          load_children(path, threshold: threshold)

          path.reverse!
          path.last.instance_variable_set('@children', [])

          childrens_hash = {}
          path.each do |m|
            next if m.id.to_s['#Thing']

            m.children.each do |c|
              childrens_hash[c.id.to_s] = c
              c.load_computed_attributes(to_load: extra_include,
                                         options: { schemes: concept_schemes, collections: concept_collections })
            end
            m.load_computed_attributes(to_load: extra_include,
                                       options: { schemes: concept_schemes, collections: concept_collections })
          end
          load_children(childrens_hash.values, threshold: threshold)
          build_tree(path, threshold: threshold)
        end

        def tree_sorted(concept_schemes: [], concept_collections: [], roots: nil)
          tr = tree(concept_schemes: concept_schemes, concept_collections: concept_collections, roots: roots)
          self.class.sort_tree_children(tr)
          tr
        end

        def paths_to_root(tree: false, roots: nil)
          bring(parents: [:prefLabel, :synonym, :definition]) if bring?(:parents)
          return [] if parents.nil? || parents.empty?

          paths = [[self]]
          traverse_path_to_root(self.parents.dup, paths, 0, tree, roots) unless tree_root?(self, roots)
          paths.each do |p|
            p.reverse!
          end
          paths
        end

        def path_to_root(roots)
          paths = [[self]]
          paths = paths_to_root(tree: true, roots: roots)
          #select one path that gets to root
          path = nil
          paths.each do |p|
            p.reverse!
            unless (p.map { |x| x.id.to_s } & roots.map { |x| x.id.to_s }).empty?
              path = p
              break
            end
          end

          if path.nil?
            # do one more check for root classes that don't get returned by the submission.roots call
            paths.each do |p|
              root_node = p.last
              root_parents = root_node.parents

              if root_parents.empty?
                path = p
                break
              end
            end
          end

          path
        end

        def tree_root?(concept, roots)
          (roots &&roots.map{|r| r.id}.include?(concept.id)) || concept.id.to_s["#Thing"]
        end
        
        private

        def load_children(concepts, threshold: 99)
          LinkedData::Models::Class
            .partially_load_children(concepts, threshold, submission)
        end

        def build_tree(path, threshold: 99)
          threshold_issue_count = 0
          root_node = path.first
          tree_node = path.first
          path.shift

          while tree_node && !tree_node.id.to_s['#Thing'] && !tree_node.children.empty? && !path.empty?

            next_tree_node = nil
            tree_node.load_has_children

            tree_node.children.each_index do |i|
              if tree_node.children[i].id.to_s == path.first.id.to_s
                next_tree_node = path.first
                children = tree_node.children.dup
                children[i] = path.first
                tree_node.instance_variable_set('@children', children)
                children.each(&:load_has_children)
              else
                tree_node.children[i].instance_variable_set('@children', [])
              end
            end

            if next_tree_node.nil? && path.size > 1 && threshold_issue_count < 5
              # max threshold issue need to load more children
              threshold_issue_count += 1
              load_children([tree_node], threshold: threshold * 10 * threshold_issue_count)
              next_tree_node = tree_node
            elsif path.size == 1
              tree_node.children << path.shift if !path.empty? && next_tree_node.nil?
            end

            path.shift unless next_tree_node.eql?(tree_node)
            tree_node = next_tree_node
          end

          root_node
        end

      end
    end

  end
end

