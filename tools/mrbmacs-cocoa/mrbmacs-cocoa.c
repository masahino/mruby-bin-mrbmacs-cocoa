#include "mrbmacs-cocoa-internal.h"

MrbmacsCocoaContext mrbmacs_cocoa;

void
mrbmacs_print_mruby_error(mrb_state *mrb)
{
  if (mrb->exc != NULL) {
    mrb_print_error(mrb);
  }
}

static void
create_application_menu(void)
{
  NSMenu *menu_bar = [[[NSMenu alloc] init] autorelease];
  NSMenuItem *application_item = [[[NSMenuItem alloc] init] autorelease];
  NSMenu *application_menu = [[[NSMenu alloc] init] autorelease];
  NSString *quit_title = [
    NSString stringWithFormat:@"Quit %@", NSProcessInfo.processInfo.processName
  ];
  NSMenuItem *quit_item = [
    [[NSMenuItem alloc]
      initWithTitle:quit_title
      action:@selector(terminate:)
      keyEquivalent:@"q"]
    autorelease
  ];

  [application_menu addItem:quit_item];
  [application_item setSubmenu:application_menu];
  [menu_bar addItem:application_item];
  [NSApp setMainMenu:menu_bar];
}

int
main(int argc, char **argv)
{
  @autoreleasepool {
    NSApplication *application = [NSApplication sharedApplication];
    struct RClass *mrbmacs;
    struct RClass *application_class;
    mrb_value mrbmacs_view;
    mrb_value mrbmacs_echo_view;
    mrb_value arg_array;
    int i;

    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    create_application_menu();
    mrbmacs_application_prepare(application);

    mrbmacs_mrb = mrb_open();
    if (mrbmacs_mrb == NULL) {
      fputs("Unable to initialize mruby\n", stderr);
      return EXIT_FAILURE;
    }

    mrbmacs = mrb_module_get(mrbmacs_mrb, "Mrbmacs");
    mrbmacs_application_register_methods(mrbmacs_mrb, mrbmacs);
    mrbmacs_frame_register_methods(mrbmacs_mrb, mrbmacs);
    mrbmacs_pane_register_methods(mrbmacs_mrb, mrbmacs);
    mrbmacs_layout_register_methods(mrbmacs_mrb, mrbmacs);
    application_class = mrb_class_get_under(
      mrbmacs_mrb, mrbmacs, "ApplicationCocoa"
    );

    arg_array = mrb_ary_new_capa(mrbmacs_mrb, argc - 1);
    for (i = 1; i < argc; i++) {
      mrb_ary_push(
        mrbmacs_mrb, arg_array, mrb_str_new_cstr(mrbmacs_mrb, argv[i])
      );
    }
    mrbmacs_app = mrb_funcall(
      mrbmacs_mrb, mrb_obj_value(application_class), "new", 1, arg_array
    );
    if (mrbmacs_mrb->exc != NULL) {
      mrbmacs_print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    mrb_gc_register(mrbmacs_mrb, mrbmacs_app);
    mrbmacs_app_ready = YES;
    mrbmacs_frame = mrb_iv_get(
      mrbmacs_mrb, mrbmacs_app, mrb_intern_lit(mrbmacs_mrb, "@frame")
    );
    mrb_gc_register(mrbmacs_mrb, mrbmacs_frame);
    mrbmacs_view = mrb_funcall(mrbmacs_mrb, mrbmacs_frame, "view", 0);
    mrb_gc_register(mrbmacs_mrb, mrbmacs_view);
    mrbmacs_echo_view = mrb_funcall(
      mrbmacs_mrb, mrbmacs_frame, "echo_win", 0
    );
    mrb_gc_register(mrbmacs_mrb, mrbmacs_echo_view);
    mrbmacs_frame_apply_initial_window_size(mrbmacs_mrb, mrbmacs_frame);
    mrb_gv_set(
      mrbmacs_mrb, mrb_intern_lit(mrbmacs_mrb, "$app"), mrbmacs_app
    );
    mrbmacs_event_install_monitor();

    [mrbmacs_window center];
    [mrbmacs_window makeKeyAndOrderFront:nil];
    [application activateIgnoringOtherApps:YES];
    mrbmacs_application_deliver_pending_open_files();
    mrb_funcall(mrbmacs_mrb, mrbmacs_view, "sci_grab_focus", 0);
    if (mrbmacs_mrb->exc != NULL) {
      mrbmacs_print_mruby_error(mrbmacs_mrb);
      mrb_close(mrbmacs_mrb);
      return EXIT_FAILURE;
    }
    [application run];

    mrbmacs_event_remove_monitor();
    mrbmacs_application_cleanup(application);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_app);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_frame);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_echo_view);
    mrb_gc_unregister(mrbmacs_mrb, mrbmacs_view);
    mrb_close(mrbmacs_mrb);
  }

  return EXIT_SUCCESS;
}
