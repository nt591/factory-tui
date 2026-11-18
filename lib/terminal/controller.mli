open Model

type focus = Board | Conversation | Activity
type input = Normal | Search | Chat_search | Compose | New_task | Edit_model
type menu_tab = Help_tab | Settings_tab
type prefix = No_prefix | Go | Window
type model_target = Task_model of string | Workspace_model of Workspace_form.t

type action =
  | Select of string
  | Zoom
  | Focus of focus
  | Start
  | Stop
  | Accept
  | Restore_task
  | Repository of string option
  | Session_board
  | Archive_view
  | Reveal_selected
  | Menu_tab of menu_tab
  | Close_menu
  | Toggle_raw_tools
  | Toggle_tools
  | Next_repository
  | Next_harness
  | Begin_model
  | Toggle_folder_root
  | Toggle_greenfield
  | Open_projects
  | Close_projects
  | Choose_project of string
  | Open_models
  | Refresh_models
  | Close_models
  | Choose_model of string
  | Toggle_archive
  | Toggle_pause
  | Help
  | Quit
  | Begin_chat_search
  | Next_chat_match
  | Previous_chat_match
  | Clear_chat_search
  | Follow_chat
  | Begin_search
  | Begin_compose
  | Open_review
  | Refresh_review
  | Edit_review_executable
  | Close_review
  | Next_review_file
  | Previous_review_file
  | Begin_workspace
  | Submit_workspace
  | Send_workspace
  | Cancel_workspace
  | Workspace_field of Workspace_form.field
  | Begin_new

type t = {
  mutable projects : Project.t list;
  mutable project_picker : Project_picker.t option;
  model_picker : Model_picker.t;
  mutable model_target : model_target option;
  mutable live_config : Live_runner.config option;
  mutable live_waiting_tasks : string list;
  mutable review : Review.t option;
  mutable jj_executable : string;
  mutable workspace_defaults : Workspace_defaults.t;
  mutable workspace_form : Workspace_form.t option;
  mutable creation_job : Task_creation.job option;
  mutable creation_send : bool;
  mutable creation_request : Task_creation.request option;
  mutable tasks : task list;
  task_updates : Task_updates.t;
  mutable selected : string;
  mutable focus : focus;
  mutable zoom : bool;
  mutable activity_expanded : bool;
  mutable activity_origin_zoom : bool;
  mutable archive : bool;
  mutable paused : bool;
  mutable help : bool;
  mutable menu_tab : menu_tab;
  mutable menu_scroll : int;
  mutable menu_page_rows : int;
  mutable repository : string option;
  mutable sidebar_scroll : int option;
  mutable tools_expanded : bool;
  mutable raw_tools : bool;
  mutable database_path : string option;
  mutable input : input;
  mutable input_limit : int option;
  mutable input_error : string option;
  mutable query : string;
  chat_search : Chat_search.t;
  chat_viewport : Chat_viewport.t;
  chat_layout : Chat_layout.t;
  tool_cache : Tool_cache.t;
  mutable new_title : string;
  mutable model_text : string;
  mutable editor : Text_edit.t;
  mutable drafts : (string * string) list;
  mutable scroll : int;
  mutable board_scroll : int;
  mutable board_list : bool;
  column_scroll : Column_scroll.t;
  pane_scroll : Pane_scroll.t;
  pane_layout : Pane_layout.t;
  mutable status : string;
  mutable quit : bool;
  mutable serial : int;
  mutable schedules : (float * envelope) list;
  mutable last_click : (string * float) option;
  mutable prefix : prefix;
  mutable count : int;
  mutable page_rows : int;
  mutable storage_events : envelope list;
  mutable retain_events : bool;
  fake_harness : bool;
  external_events : bool;
}

val create : ?external_events:bool -> ?fake_harness:bool -> unit -> t
val contains : string -> string -> bool
val visible : t -> Model.task list
val repositories : t -> string list
val selected : t -> Model.task option
val draft : t -> string
val repair_selection : t -> unit
val reset_keys : t -> unit
val receive : t -> Model.envelope -> unit
val snapshot : t -> Snapshot.t
val restore : t -> Snapshot.t -> unit
val tick : t -> float -> unit
val act : t -> action -> unit
val clean : ?newlines:bool -> string -> string
val remove_last : string -> string
val set_input : t -> string -> unit
val submit : t -> unit
val key : t -> Notty.Unescape.key -> unit
val insert_text : t -> string -> unit
val paste_key : t -> Notty.Unescape.key -> unit
val demo_context : t -> Demo.Runner.context
val poll_creation : t -> storage:Persistence.t option -> unit
val finish_creation : t -> storage:Persistence.t option -> unit
val enable_live : t -> Live_runner.config -> (unit, string) result
val live_context : t -> Live_runner.context
val set_workspace_defaults : t -> Workspace_defaults.t -> unit

val initialize_board :
  t -> saved:Snapshot.t option -> live:Live_runner.config option -> (unit, string) result
