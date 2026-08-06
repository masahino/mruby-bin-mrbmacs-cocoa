module Mrbmacs
  # Cocoa implementations for commands that require echo-area interaction.
  module Command
    def replace_string
      start_replace(false)
    end

    def query_replace
      start_replace(true)
    end

    def select_font
      @frame.select_font
    end
  end

end
