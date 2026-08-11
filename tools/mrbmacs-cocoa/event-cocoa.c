#include "mrbmacs-cocoa-internal.h"

static NSString *
mrbmacs_key_name(NSEvent *event)
{
  NSEventModifierFlags modifiers =
    event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  NSString *characters;
  NSString *prefix = @"";

  if ((modifiers & NSEventModifierFlagCommand) != 0) {
    return nil;
  }
  characters = event.charactersIgnoringModifiers;
  if (characters.length == 0) {
    return nil;
  }
  if ((modifiers & NSEventModifierFlagControl) != 0) {
    prefix = @"C-";
  } else if ((modifiers & NSEventModifierFlagOption) != 0) {
    prefix = @"M-";
  }

  switch ([characters characterAtIndex:0]) {
  case 0x00:
    characters = @" ";
    break;
  case 0x1b:
    return @"Escape";
  case '\r':
    characters = @"Enter";
    break;
  case '\t':
    characters = @"Tab";
    break;
  case 0x7f:
    characters = @"DEL";
    break;
  default:
    characters = [characters lowercaseString];
    break;
  }
  return [prefix stringByAppendingString:characters];
}

static NSEvent *
mrbmacs_handle_key_event(NSEvent *event)
{
  NSString *key = mrbmacs_key_name(event);
  mrb_value handled;
  NSResponder *responder;
  BOOL echo_is_responder;

  if (key == nil) {
    return event;
  }
  responder = NSApp.keyWindow.firstResponder;
  echo_is_responder = [responder isEqual:mrbmacs_echo_native_view] ||
    ([responder isKindOfClass:[NSView class]] &&
     [(NSView *)responder isDescendantOf:mrbmacs_echo_native_view]);
  if (NSApp.modalWindow != nil && echo_is_responder) {
    if (mrbmacs_confirmation_input) {
      if ([key isEqualToString:@"y"]) {
        [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_YES];
        return nil;
      }
      if ([key isEqualToString:@"n"] || [key isEqualToString:@"C-g"]) {
        [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_NO];
        return nil;
      }
      return nil;
    }
    if ([key isEqualToString:@"Enter"]) {
      [NSApp stopModalWithCode:NSModalResponseOK];
      return nil;
    }
    if ([key isEqualToString:@"C-g"]) {
      [NSApp stopModalWithCode:NSModalResponseCancel];
      return nil;
    }
    if ([key isEqualToString:@"Tab"]) {
      [NSApp stopModalWithCode:MRBMACS_MODAL_RESPONSE_TAB];
      return nil;
    }
    return event;
  }
  if (echo_is_responder) {
    handled = mrb_funcall(
      mrbmacs_mrb, mrbmacs_app, "echo_key_press", 1,
      mrb_str_new_cstr(mrbmacs_mrb, key.UTF8String)
    );
    if (mrbmacs_mrb->exc != NULL) {
      mrbmacs_print_mruby_error(mrbmacs_mrb);
      return event;
    }
    return mrb_test(handled) ? nil : event;
  }
  handled = mrb_funcall(
    mrbmacs_mrb, mrbmacs_app, "key_press", 1,
    mrb_str_new_cstr(mrbmacs_mrb, key.UTF8String)
  );
  if (mrbmacs_mrb->exc != NULL) {
    mrbmacs_print_mruby_error(mrbmacs_mrb);
    return event;
  }
  return mrb_test(handled) ? nil : event;
}

void
mrbmacs_event_install_monitor(void)
{
  key_event_monitor = [NSEvent
    addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
    handler:^NSEvent *(NSEvent *event) {
      return mrbmacs_handle_key_event(event);
    }
  ];
}

void
mrbmacs_event_remove_monitor(void)
{
  [NSEvent removeMonitor:key_event_monitor];
}


