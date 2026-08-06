module Mrbmacs
  # A branch in a tab's pane layout tree.
  class SplitCocoa
    attr_reader :orientation
    attr_accessor :first, :second, :parent

    def initialize(orientation, first, second)
      @orientation = orientation
      @parent = nil
      self.first = first
      self.second = second
    end

    def first=(node)
      @first = node
      node.parent = self
    end

    def second=(node)
      @second = node
      node.parent = self
    end

    def panes
      first_panes = @first.is_a?(PaneCocoa) ? [@first] : @first.panes
      second_panes = @second.is_a?(PaneCocoa) ? [@second] : @second.panes
      first_panes + second_panes
    end
  end

  # One tab represents a complete editor layout, not a buffer.
  class TabCocoa
    attr_reader :layout_root
    attr_accessor :active_pane

    def initialize(pane)
      @layout_root = pane
      @active_pane = pane
    end

    def panes
      collect_panes(@layout_root)
    end

    def split(pane, new_pane, orientation)
      parent = pane.parent
      split = SplitCocoa.new(orientation, pane, new_pane)
      if parent.nil?
        @layout_root = split
        split.parent = nil
      elsif parent.first.equal?(pane)
        parent.first = split
      else
        parent.second = split
      end
      split
    end

    def delete(pane)
      return nil if pane.equal?(@layout_root)

      parent = pane.parent
      sibling = parent.first.equal?(pane) ? parent.second : parent.first
      replace_node(parent, sibling)
      pane.parent = nil
      sibling.is_a?(PaneCocoa) ? sibling : sibling.panes.first
    end

    def keep_only(pane)
      @layout_root = pane
      pane.parent = nil
      @active_pane = pane
    end

    private

    def collect_panes(node)
      return [node] if node.is_a?(PaneCocoa)

      collect_panes(node.first) + collect_panes(node.second)
    end

    def replace_node(old_node, new_node)
      parent = old_node.parent
      if parent.nil?
        @layout_root = new_node
        new_node.parent = nil
      elsif parent.first.equal?(old_node)
        parent.first = new_node
      else
        parent.second = new_node
      end
    end
  end

end
