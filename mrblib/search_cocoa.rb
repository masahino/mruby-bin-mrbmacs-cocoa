module Mrbmacs
  class ApplicationCocoa < Application
    def echo_sci_notify(_notification)
      return unless @isearch_active
      return if @isearch_setting_text

      text = @frame.echo_win.sci_get_line(0)
      return if text == @isearch_text

      @isearch_text = text
      if text.empty?
        @frame.view.sci_goto_pos(@isearch_origin)
        @frame.modeline(self)
        return
      end
      @last_search_text = text unless text.empty?
      perform_isearch(@isearch_origin)
    end

    def isearch_active?
      @isearch_active
    end

    def isearch_forward
      start_or_repeat_isearch(false)
    end

    def isearch_backward
      start_or_repeat_isearch(true)
    end

    def start_or_repeat_isearch(backward)
      if @isearch_active
        @isearch_backward = backward
        @frame.update_isearch_prompt(isearch_prompt)
        repeat_isearch
        return
      end

      @isearch_active = true
      @isearch_backward = backward
      @isearch_origin = @frame.view.sci_get_current_pos
      @isearch_text = ''
      @frame.start_isearch(isearch_prompt)
    end

    def repeat_isearch
      if @isearch_text.empty?
        return if @last_search_text.empty?

        @isearch_text = @last_search_text
        begin
          @isearch_setting_text = true
          @frame.set_isearch_text(@isearch_text)
          @frame.update_isearch_prompt(isearch_prompt)
        ensure
          @isearch_setting_text = false
        end
      end
      view = @frame.view
      start_pos = if @isearch_backward
                    view.sci_get_selection_start
                  else
                    view.sci_get_selection_end
                  end
      perform_isearch(start_pos, true)
    end

    def perform_isearch(start_pos, wrap = false)
      return if @isearch_text.empty?

      view = @frame.view
      end_pos = @isearch_backward ? 0 : view.sci_get_length
      view.sci_set_target_start(start_pos)
      view.sci_set_target_end(end_pos)
      found = view.sci_search_in_target(
        @isearch_text.bytesize, @isearch_text
      )
      if found == -1 && wrap
        view.sci_set_target_start(
          @isearch_backward ? view.sci_get_length : 0
        )
        view.sci_set_target_end(@isearch_origin)
        found = view.sci_search_in_target(
          @isearch_text.bytesize, @isearch_text
        )
      end
      return if found == -1

      view.sci_set_sel(view.sci_get_target_start, view.sci_get_target_end)
      @frame.modeline(self)
    end

    def finish_isearch(cancel)
      @frame.view.sci_goto_pos(@isearch_origin) if cancel
      @isearch_active = false
      @frame.finish_isearch
      @frame.modeline(self)
    end

    def isearch_prompt
      @isearch_backward ? 'I-search backward: ' : 'I-search: '
    end

    # Like the terminal frontends, Cocoa currently switches documents in the
    # active pane. Native tab creation will be added with the tab UI.
  end
end
