#ifndef MRBMACS_COCOA_INTERNAL_H
#define MRBMACS_COCOA_INTERNAL_H

#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include <mruby/variable.h>

typedef struct {
  mrb_state *mrb;
  mrb_value frame;
  mrb_value app;
  BOOL app_ready;
  id key_event_monitor;
  id application_delegate;
  NSWindow *window;
  NSView *echo_native_view;
  BOOL confirmation_input;
  id font_target;
  NSMutableDictionary *io_sources;
  NSMutableArray *pending_open_paths;
} MrbmacsCocoaContext;

extern MrbmacsCocoaContext mrbmacs_cocoa;

#define mrbmacs_mrb mrbmacs_cocoa.mrb
#define mrbmacs_frame mrbmacs_cocoa.frame
#define mrbmacs_app mrbmacs_cocoa.app
#define mrbmacs_app_ready mrbmacs_cocoa.app_ready
#define key_event_monitor mrbmacs_cocoa.key_event_monitor
#define mrbmacs_application_delegate mrbmacs_cocoa.application_delegate
#define mrbmacs_window mrbmacs_cocoa.window
#define mrbmacs_echo_native_view mrbmacs_cocoa.echo_native_view
#define mrbmacs_confirmation_input mrbmacs_cocoa.confirmation_input
#define mrbmacs_font_target mrbmacs_cocoa.font_target
#define mrbmacs_io_sources mrbmacs_cocoa.io_sources
#define mrbmacs_pending_open_paths mrbmacs_cocoa.pending_open_paths

enum {
  MRBMACS_MODAL_RESPONSE_TAB = 1001,
  MRBMACS_MODAL_RESPONSE_YES,
  MRBMACS_MODAL_RESPONSE_NO
};

void mrbmacs_print_mruby_error(mrb_state *mrb);

void mrbmacs_application_prepare(NSApplication *application);
void mrbmacs_application_register_methods(mrb_state *mrb,
                                          struct RClass *mrbmacs);
void mrbmacs_application_deliver_pending_open_files(void);
void mrbmacs_application_schedule_pending_open_files(void);
void mrbmacs_application_cleanup(NSApplication *application);

void mrbmacs_frame_register_methods(mrb_state *mrb,
                                    struct RClass *mrbmacs);
void mrbmacs_frame_apply_initial_window_size(mrb_state *mrb,
                                             mrb_value frame);

NSView *mrbmacs_pane_create_native_view(mrb_state *mrb, mrb_value pane);
void mrbmacs_pane_register_methods(mrb_state *mrb,
                                   struct RClass *mrbmacs);

void mrbmacs_layout_register_methods(mrb_state *mrb,
                                     struct RClass *mrbmacs);

void mrbmacs_event_install_monitor(void);
void mrbmacs_event_remove_monitor(void);

#endif
