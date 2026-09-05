module Mrbmacs
  # Cocoa implementations for commands that require echo-area interaction.
  module Command
    def select_font
      @frame.select_font
    end
  end

end
