with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Ada_Source;
with Project_Tools.Alire_Manifests;
with Project_Tools.AUnit_Checks;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Text;
with Project_Tools.Tree_Checks;

procedure Check_Regexp is
   use Ada.Text_IO;
   use type Ada.Directories.File_Kind;

   function Root_Directory return String is
      Current : constant String := Ada.Directories.Current_Directory;
      Found   : constant String := Project_Tools.Files.Find_Root_Upward (Current, "regexp.gpr");
   begin
      if Found /= ""
        and then Ada.Directories.Exists (Found & "/docs/api-reference.md")
      then
         return Found;
      else
         Put_Line (Standard_Error, "regexp root not found from " & Current);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Root_Directory;

   Root : constant String := Root_Directory;

   procedure Require_Text (Relative_Path : String; Text : String) is
   begin
      Project_Tools.Files.Require_Contains
        (Root & "/" & Relative_Path,
         Text,
         "missing expected text in " & Relative_Path & ": " & Text,
         Quiet => False);
   end Require_Text;

   procedure Require_Documented_Example (Relative_Path : String) is
   begin
      Require_Text ("README.md", Ada.Directories.Simple_Name (Relative_Path));
      Project_Tools.Files.Require_File
        (Root & "/" & Relative_Path,
         "documented example does not exist",
         Quiet => False);
   end Require_Documented_Example;

   procedure Require_Release_Tree_Clean is
      use Ada.Strings.Unbounded;

      Stage               : constant String := "/tmp/regexp-release-tree-check";
      Generated_Entries   : constant Project_Tools.Tree_Checks.Text_List :=
        [To_Unbounded_String ("alire"),
         To_Unbounded_String ("bin"),
         To_Unbounded_String ("config"),
         To_Unbounded_String ("lib"),
         To_Unbounded_String ("obj")];
      Generated_Suffixes  : constant Project_Tools.Tree_Checks.Text_List :=
        [To_Unbounded_String (".ali"),
         To_Unbounded_String (".o"),
         To_Unbounded_String (".bexch"),
         To_Unbounded_String (".stdout"),
         To_Unbounded_String (".stderr"),
         To_Unbounded_String (".cswi")];
      Errors              : Natural := 0;
   begin
      Project_Tools.Files.Delete_Tree (Stage);
      Project_Tools.Files.Copy_Release_Source_Tree
        (Source_Dir   => Root,
         Target_Dir   => Stage,
         Skip_Entries =>
           [To_Unbounded_String (".git"),
            To_Unbounded_String ("alire"),
            To_Unbounded_String ("bin"),
            To_Unbounded_String ("config"),
            To_Unbounded_String ("lib"),
            To_Unbounded_String ("obj")],
         Skip_Files   =>
           [To_Unbounded_String ("alire.lock"),
            To_Unbounded_String ("alire.lock.prev"),
            To_Unbounded_String ("alire.toml.prev")],
         Quiet        => False);

      Project_Tools.Tree_Checks.Check_No_Forbidden_Tree_Artifacts
        (Errors,
         Stage,
         Generated_Entries,
         Generated_Suffixes,
         "staged release tree",
         Quiet => False);
      Project_Tools.Tree_Checks.Check_No_Generated_Python (Errors, Stage, Quiet => False);
      Project_Tools.Files.Delete_Tree (Stage);

      if Errors /= 0 then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   exception
      when others =>
         Project_Tools.Files.Delete_Tree (Stage);
         raise;
   end Require_Release_Tree_Clean;

   procedure Require_Examples_Inventory is
      Readme    : constant String := Project_Tools.Files.Read_Raw_File (Root & "/README.md");
      Search    : Ada.Directories.Search_Type;
      Open      : Boolean := False;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Filter    : constant Ada.Directories.Filter_Type :=
        [Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False];
   begin
      Project_Tools.Release_Checks.Require_GPR_Main_Inventory
        (Project_File       => Root & "/examples/examples.gpr",
         Documentation_File => Root & "/README.md",
         Source_Directory   => Root & "/examples/src",
         Quiet              => False);

      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Root & "/examples/src",
         Pattern   => "*.adb",
         Filter    => Filter);
      Open := True;

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);

         declare
            Example_Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
         begin
            if not Project_Tools.Text.Contains (Readme, Example_Name) then
               Put_Line (Standard_Error, "example missing from README.md: " & Example_Name);
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               raise Program_Error;
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
      Open := False;
   exception
      when others =>
         if Open then
            Ada.Directories.End_Search (Search);
         end if;
         raise;
   end Require_Examples_Inventory;

   procedure Require_Manifest_Policy is
   begin
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Manifest      => Root & "/check_regexp/alire.toml",
         Crate         => "regexp",
         Relative_Path => "..",
         Quiet         => False);
      Project_Tools.Alire_Manifests.Require_Workspace_Pin
        (Manifest      => Root & "/check_regexp/alire.toml",
         Crate         => "project_tools",
         Relative_Path => "../../project_tools",
         Quiet         => False);
      Project_Tools.Alire_Manifests.Require_Pin_Free_Crate_Manifest
        (Manifest => Root & "/check_regexp/alire.release.toml",
         Name     => "check_regexp",
         Quiet    => False);
      Project_Tools.Alire_Manifests.Require_Release_Dependencies
        (Manifest     => Root & "/check_regexp/alire.release.toml",
         Dependencies =>
           [Ada.Strings.Unbounded.To_Unbounded_String ("regexp"),
            Ada.Strings.Unbounded.To_Unbounded_String ("project_tools")],
         Quiet        => False);
   end Require_Manifest_Policy;

   procedure Require_Check_Regexp_Staging_Workflow is
      use Ada.Strings.Unbounded;

      Workspace     : constant String := "/tmp/regexp-check-regexp-staging";
      Staged_Root   : constant String := Workspace & "/regexp";
      Staged_Check  : constant String := Staged_Root & "/check_regexp";
      Staged_Tools  : constant String := Workspace & "/project_tools";
      Release       : constant String := Root & "/check_regexp/alire.release.toml";
      Build         : constant String := Staged_Check & "/alire.build.toml";
      Pins          : constant String :=
        "[[pins]]" & ASCII.LF
        & "regexp = { path = '..' }" & ASCII.LF
        & ASCII.LF
        & "[[pins]]" & ASCII.LF
        & "project_tools = { path = '../../project_tools' }" & ASCII.LF;
      Alr           : constant String := Project_Tools.Processes.Locate_Command ("alr");
   begin
      Project_Tools.Processes.Require_Command
        ("alr", "alr executable not found on PATH");
      Project_Tools.Files.Delete_Tree (Workspace);
      Project_Tools.Files.Copy_Release_Source_Tree
        (Source_Dir   => Root,
         Target_Dir   => Staged_Root,
         Skip_Entries =>
           [To_Unbounded_String (".git"),
            To_Unbounded_String ("alire"),
            To_Unbounded_String ("bin"),
            To_Unbounded_String ("config"),
            To_Unbounded_String ("lib"),
            To_Unbounded_String ("obj")],
         Skip_Files   =>
           [To_Unbounded_String ("alire.lock"),
            To_Unbounded_String ("alire.lock.prev"),
            To_Unbounded_String ("alire.toml.prev")],
         Quiet        => False);
      Project_Tools.Files.Copy_Release_Source_Tree
        (Source_Dir   => Root & "/../project_tools",
         Target_Dir   => Staged_Tools,
         Skip_Entries =>
           [To_Unbounded_String (".git"),
            To_Unbounded_String ("alire"),
            To_Unbounded_String ("bin"),
            To_Unbounded_String ("config"),
            To_Unbounded_String ("lib"),
            To_Unbounded_String ("obj")],
         Skip_Files   =>
           [To_Unbounded_String ("alire.lock"),
            To_Unbounded_String ("alire.lock.prev"),
            To_Unbounded_String ("alire.toml.prev")],
         Quiet        => False);

      Project_Tools.Alire_Manifests.Copy_Release_Manifest
        (Template => Release,
         Target   => Staged_Check & "/alire.toml",
         Quiet    => False);
      Ada.Directories.Copy_File
        (Source_Name => Root & "/LICENSE",
         Target_Name => Staged_Check & "/LICENSE",
         Form        => "mode=overwrite");
      Project_Tools.Alire_Manifests.Write_Build_Manifest_Overlay
        (Template => Release,
         Target   => Build,
         Pins     => Pins,
         Quiet    => False);
      Project_Tools.Alire_Manifests.Require_Build_Overlay
        (Overlay      => Build,
         Template     => Release,
         Dependencies =>
           [To_Unbounded_String ("regexp = { path = '..' }"),
            To_Unbounded_String ("project_tools = { path = '../../project_tools' }")],
         Quiet        => False);
      Project_Tools.Alire_Manifests.Require_Staged_Crate_Source
        (Crate_Dir => Staged_Check,
         Name      => "check_regexp",
         GPR_File  => "check_regexp.gpr",
         Quiet     => False);
      Project_Tools.Alire_Manifests.Activate_Build_Manifest (Staged_Check, Quiet => False);
      Project_Tools.Release_Checks.Run
        ("staged check_regexp build",
         Staged_Check,
         Alr,
         [1 => new String'("build")]);
      Project_Tools.Alire_Manifests.Restore_Publish_Manifest (Staged_Check);
      Project_Tools.Files.Delete_Tree (Workspace);
   exception
      when others =>
         Project_Tools.Alire_Manifests.Restore_Publish_Manifest (Staged_Check);
         Project_Tools.Files.Delete_Tree (Workspace);
         raise;
   end Require_Check_Regexp_Staging_Workflow;

   procedure Require_Example_Public_API_Only is
      Empty : Project_Tools.Ada_Source.String_List (1 .. 0);
   begin
      for Path of Project_Tools.Files.List_Tree (Root & "/examples/src", "*.adb") loop
         Project_Tools.Ada_Source.Require_Only_Allowed_With_Clauses
           (Source_Path => Ada.Strings.Unbounded.To_String (Path),
            Prefix      => "Regexp.",
            Allowed     => Empty,
            Quiet       => False);
      end loop;
   end Require_Example_Public_API_Only;

   procedure Require_Example_Failure_Handling is
   begin
      for Path of Project_Tools.Files.List_Tree (Root & "/examples/src", "*.adb") loop
         declare
            File : constant String := Ada.Strings.Unbounded.To_String (Path);
         begin
            Project_Tools.Files.Require_Contains
              (File,
               "Ada.Command_Line.Set_Exit_Status",
               "example must set nonzero exit status on failure: " & File,
               Quiet => False);
            Project_Tools.Files.Require_Contains
              (File,
               "Status",
               "example must check regexp statuses: " & File,
               Quiet => False);
         end;
      end loop;
   end Require_Example_Failure_Handling;

   procedure Require_Example_Outputs is
      procedure Check (Name : String) is
      begin
         Project_Tools.Release_Checks.Require_Program_Output_Matches_Fenced_Text
           (Expected_File => Root & "/examples/README.md",
            Fence_Label   => "text " & Name,
            Dir           => Root,
            Program       => Root & "/examples/bin/" & Name,
            Args          => [],
            Label         => "example " & Name,
            Quiet         => False);
      end Check;
   begin
      Check ("basic_search");
      Check ("case_sensitivity");
      Check ("whole_word");
      Check ("find_from_offsets");
      Check ("find_all_matches");
      Check ("matches_entire");
      Check ("character_classes");
      Check ("preset_patterns");
      Check ("lookaround_options");
      Check ("search_workflow");
      Check ("advanced_search_planning");
      Check ("compile_errors");
      Check ("step_limit");
   end Require_Example_Outputs;

   procedure Require_Source_Policy is
      use Ada.Strings.Unbounded;

      Forbidden_Code : constant Project_Tools.Ada_Source.String_List :=
        [To_Unbounded_String ("go" & "to")];
      Tooling_Tokens : constant Project_Tools.Tree_Checks.Text_List :=
        [To_Unbounded_String ("Project_Tools"),
         To_Unbounded_String ("project_tools")];
      Errors : Natural := 0;

      procedure Require_No_Forbidden_Code (Dir : String) is
      begin
         for Path of Project_Tools.Files.List_Tree (Dir, "*.ads") loop
            Project_Tools.Ada_Source.Require_No_Code_Tokens
              (Ada.Strings.Unbounded.To_String (Path), Forbidden_Code, Quiet => False);
         end loop;

         for Path of Project_Tools.Files.List_Tree (Dir, "*.adb") loop
            Project_Tools.Ada_Source.Require_No_Code_Tokens
              (Ada.Strings.Unbounded.To_String (Path), Forbidden_Code, Quiet => False);
         end loop;
      end Require_No_Forbidden_Code;
   begin
      Project_Tools.Ada_Source.Require_Public_GNATdoc_Tags
        (Spec_Path       => Root & "/src/regexp.ads",
         Stop_At_Private => True,
         Tags_Before     => True,
         Quiet           => False);

      Require_No_Forbidden_Code (Root & "/src");
      Require_No_Forbidden_Code (Root & "/tests/src");
      Require_No_Forbidden_Code (Root & "/examples/src");
      Require_No_Forbidden_Code (Root & "/tools");
      Require_No_Forbidden_Code (Root & "/check_regexp/src");

      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors,
         Root & "/src",
         Tooling_Tokens,
         "library source",
         Quiet => False);
      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors,
         Root & "/tests/src",
         Tooling_Tokens,
         "test source",
         Quiet => False);
      Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
        (Errors,
         Root & "/examples/src",
         Tooling_Tokens,
         "example source",
         Quiet => False);

      if Errors /= 0 then
         raise Program_Error;
      end if;
   end Require_Source_Policy;

   procedure Require_AUnit_Inventory is
   begin
      Project_Tools.AUnit_Checks.Require_Registered_Test_Packages
        (Test_Dir           => Root & "/tests/src",
         Spec_Pattern       => "regexp_tests-*tests.ads",
         Suite_Path         => Root & "/tests/src/regexp_tests.adb",
         Suite_Add_Prefix   => "Ret.Add_Test (new ",
         Suite_Add_Suffix   => ".Test_Case);",
         Registration_Token => "Register_Routine",
         Quiet              => False);
   end Require_AUnit_Inventory;

begin
   Project_Tools.Files.Require_Files
     ([Ada.Strings.Unbounded.To_Unbounded_String (Root & "/README.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/alire.toml"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/regexp.gpr"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/src/regexp.ads"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/api-reference.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/SPARK.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/ai-usage.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/ai-index.json"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/llms.txt"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/examples/README.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/check_regexp/README.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/check_regexp/alire.release.toml"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/tools/check_all.adb"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/tools/tools.gpr")],
      "required regexp release file missing",
      Quiet => False);

   Require_Text ("LICENSE", "MIT License");
   Require_Text ("LICENSE", "Apache License");
   Require_Text ("LICENSE", "LLVM Exceptions");
   Require_Text ("alire.toml", "MIT OR Apache-2.0 WITH LLVM-exception");

   Require_Text ("README.md", "LICENSE");
   Require_Text ("README.md", "alr exec -- gnatprove -P regexp.gpr --level=4");
   Require_Text ("README.md", "docs/SPARK.md");
   Require_Text ("README.md", "alr test");
   Require_Text ("README.md", "docs/api-reference.md");
   Require_Text ("README.md", "docs/ai-usage.md");
   Require_Text ("README.md", "llms.txt");
   Require_Text ("README.md", "alr exec -- gprbuild -P regexp.gpr");
   Require_Text ("README.md", "tests/bin/tests");
   Require_Text ("README.md", "tools/bin/check_all");
   Require_Text ("README.md", "check_regexp");
   Require_Text ("README.md", "check_regexp/alire.release.toml");
   Require_Text ("README.md", "clean Git worktree");

   Require_Text ("docs/api-reference.md", "package Regexp is");
   Require_Text ("docs/api-reference.md", "Compile_Result");
   Require_Text ("docs/api-reference.md", "Match_Options");
   Require_Text ("docs/api-reference.md", "Find_First");
   Require_Text ("docs/api-reference.md", "Find_From");
   Require_Text ("docs/api-reference.md", "Find_All");
   Require_Text ("docs/api-reference.md", "Find_All_From");
   Require_Text ("docs/api-reference.md", "Compile_Literal");
   Require_Text ("docs/api-reference.md", "Compile_Literal_Set");
   Require_Text ("docs/api-reference.md", "Compile_Literal_Word_Set");
   Require_Text ("docs/api-reference.md", "Compile_Anchored");
   Require_Text ("docs/api-reference.md", "Compile_Whole_Word");
   Require_Text ("docs/api-reference.md", "Compile_Literal_Anchored");
   Require_Text ("docs/api-reference.md", "Compile_Literal_Whole_Word");
   Require_Text ("docs/api-reference.md", "Compile_Line");
   Require_Text ("docs/api-reference.md", "Compile_Literal_Line");
   Require_Text ("docs/api-reference.md", "Default_Options");
   Require_Text ("docs/api-reference.md", "Case_Sensitive_Options");
   Require_Text ("docs/api-reference.md", "Multiline_Options");
   Require_Text ("docs/api-reference.md", "Dot_All_Options");
   Require_Text ("docs/api-reference.md", "Character_Mode_Type");
   Require_Text ("docs/api-reference.md", "ASCII_Mode");
   Require_Text ("docs/api-reference.md", "UTF_8_Mode");
   Require_Text ("docs/api-reference.md", "UTF_8_Options");
   Require_Text ("docs/api-reference.md", "Validate_UTF_8");
   Require_Text ("docs/api-reference.md", "UTF_8_Validation_Result");
   Require_Text ("docs/api-reference.md", "Supports_Syntax");
   Require_Text ("docs/api-reference.md", "Syntax_Feature");
   Require_Text ("docs/api-reference.md", "Syntax_Feature_Image");
   Require_Text ("docs/api-reference.md", "Supported_Syntax");
   Require_Text ("docs/api-reference.md", "Supported_Syntax_Detail");
   Require_Text ("docs/api-reference.md", "Syntax_Support");
   Require_Text ("docs/api-reference.md", "Syntax_Support_Array");
   Require_Text ("docs/api-reference.md", "Escape_Literal");
   Require_Text ("docs/api-reference.md", "Escape_Replacement");
   Require_Text ("docs/api-reference.md", "Append_Fragment");
   Require_Text ("docs/api-reference.md", "Append_Literal");
   Require_Text ("docs/api-reference.md", "Append_Literal_Alternative");
   Require_Text ("docs/api-reference.md", "Append_Class_Literal");
   Require_Text ("docs/api-reference.md", "Append_Class_Range");
   Require_Text ("docs/api-reference.md", "Build_Character_Class");
   Require_Text ("docs/api-reference.md", "Build_Literal_Alternation");
   Require_Text ("docs/api-reference.md", "Build_Literal_Word_Alternation");
   Require_Text ("docs/api-reference.md", "Is_Literal");
   Require_Text ("docs/api-reference.md", "Is_Anchored");
   Require_Text ("docs/api-reference.md", "Is_Whole_Line");
   Require_Text ("docs/api-reference.md", "Needs_Backtracking");
   Require_Text ("docs/api-reference.md", "Can_Stream_Safely");
   Require_Text ("docs/api-reference.md", "Recommended_Strategy");
   Require_Text ("docs/api-reference.md", "Search_Strategy");
   Require_Text ("docs/api-reference.md", "Expression_Summary");
   Require_Text ("docs/api-reference.md", "Pattern_Source_Kind");
   Require_Text ("docs/api-reference.md", "Summary");
   Require_Text ("docs/api-reference.md", "Fingerprint");
   Require_Text ("docs/api-reference.md", "Pattern_Fingerprint");
   Require_Text ("docs/api-reference.md", "Metadata");
   Require_Text ("docs/api-reference.md", "Pattern_Metadata");
   Require_Text ("docs/api-reference.md", "Source_Kind");
   Require_Text ("docs/api-reference.md", "Copy_Source_Pattern");
   Require_Text ("docs/api-reference.md", "Pattern_Lint");
   Require_Text ("docs/api-reference.md", "Lint");
   Require_Text ("docs/api-reference.md", "Compile_Diagnostic");
   Require_Text ("docs/api-reference.md", "Replacement_Diagnostic");
   Require_Text ("docs/api-reference.md", "Count_Matches");
   Require_Text ("docs/api-reference.md", "Find_First_Of");
   Require_Text ("docs/api-reference.md", "Find_From_Of");
   Require_Text ("docs/api-reference.md", "Tokenize");
   Require_Text ("docs/api-reference.md", "Tokenize_With_Kinds");
   Require_Text ("docs/api-reference.md", "Find_First_Of_With_Captures");
   Require_Text ("docs/api-reference.md", "Find_From_Of_With_Captures");
   Require_Text ("docs/api-reference.md", "Tokenize_With_Captures");
   Require_Text ("docs/api-reference.md", "Find_From_Planned");
   Require_Text ("docs/api-reference.md", "Find_From_Planned_With_Captures");
   Require_Text ("docs/api-reference.md", "Replace_All");
   Require_Text ("docs/api-reference.md", "Replace_First_Count");
   Require_Text ("docs/api-reference.md", "Replace_All_Count");
   Require_Text ("docs/api-reference.md", "Replace_All_Preserving_Case");
   Require_Text ("docs/api-reference.md", "Validate_Replacement");
   Require_Text ("docs/api-reference.md", "Validate_Replacement_Detail");
   Require_Text ("docs/api-reference.md", "Replacement_References");
   Require_Text ("docs/api-reference.md", "Replacement_Summary");
   Require_Text ("docs/api-reference.md", "Replacement_Features");
   Require_Text ("docs/api-reference.md", "Replacement_Reference_Array");
   Require_Text ("docs/api-reference.md", "Replacement_Validation_Result");
   Require_Text ("docs/api-reference.md", "Replacement_Validation_Status");
   Require_Text ("docs/api-reference.md", "Required_First_Output_Length");
   Require_Text ("docs/api-reference.md", "Required_All_Output_Length");
   Require_Text ("docs/api-reference.md", "Replacement_Fits");
   Require_Text ("docs/api-reference.md", "Plan_Replacement");
   Require_Text ("docs/api-reference.md", "Plan_Replacement_Detail");
   Require_Text ("docs/api-reference.md", "Replacement_Output_Map");
   Require_Text ("docs/api-reference.md", "Replacement_Plan");
   Require_Text ("docs/api-reference.md", "\k<name>");
   Require_Text ("docs/api-reference.md", "\U...\E");
   Require_Text ("docs/api-reference.md", "Split");
   Require_Text ("docs/api-reference.md", "Split_Lines");
   Require_Text ("docs/api-reference.md", "Copy_Match");
   Require_Text ("docs/api-reference.md", "Debug_Dump");
   Require_Text ("docs/api-reference.md", "Explain");
   Require_Text ("docs/api-reference.md", "Explain_Nodes");
   Require_Text ("docs/api-reference.md", "Format_Compile_Diagnostic");
   Require_Text ("docs/api-reference.md", "Format_Replacement_Diagnostic");
   Require_Text ("docs/api-reference.md", "Capture_Count");
   Require_Text ("docs/api-reference.md", "Capture_Index");
   Require_Text ("docs/api-reference.md", "Named_Captures");
   Require_Text ("docs/api-reference.md", "Capture_Index_Array");
   Require_Text ("docs/api-reference.md", "Capture_Name");
   Require_Text ("docs/api-reference.md", "Has_Captures");
   Require_Text ("docs/api-reference.md", "Uses_Anchors");
   Require_Text ("docs/api-reference.md", "May_Match_Empty");
   Require_Text ("docs/api-reference.md", "Required_Prefix");
   Require_Text ("docs/api-reference.md", "Features");
   Require_Text ("docs/api-reference.md", "Pattern_Features");
   Require_Text ("docs/api-reference.md", "Validate_Policy");
   Require_Text ("docs/api-reference.md", "Validate_Policy_Detail");
   Require_Text ("docs/api-reference.md", "Pattern_Policy_Diagnostic");
   Require_Text ("docs/api-reference.md", "Policy_Feature");
   Require_Text ("docs/api-reference.md", "Pattern_Policy");
   Require_Text ("docs/api-reference.md", "Literal_Search_Policy");
   Require_Text ("docs/api-reference.md", "Editor_Search_Policy");
   Require_Text ("docs/api-reference.md", "No_Backtracking_Features_Policy");
   Require_Text ("docs/api-reference.md", "Safe_User_Search_Policy");
   Require_Text ("docs/api-reference.md", "Streaming_Search_Policy");
   Require_Text ("docs/api-reference.md", "Editor_Replace_Policy");
   Require_Text ("docs/api-reference.md", "No_Empty_Match_Policy");
   Require_Text ("docs/api-reference.md", "No_Lookaround_Policy");
   Require_Text ("docs/api-reference.md", "No_Backreferences_Policy");
   Require_Text ("docs/api-reference.md", "Line_Column");
   Require_Text ("docs/api-reference.md", "Match_Line_Range");
   Require_Text ("docs/api-reference.md", "Match_Length");
   Require_Text ("docs/api-reference.md", "Contains_Offset");
   Require_Text ("docs/api-reference.md", "Before_Match");
   Require_Text ("docs/api-reference.md", "After_Match");
   Require_Text ("docs/api-reference.md", "Match_Context");
   Require_Text ("docs/api-reference.md", "Find_First_Line");
   Require_Text ("docs/api-reference.md", "Copy_Range");
   Require_Text ("docs/api-reference.md", "Copy_Before");
   Require_Text ("docs/api-reference.md", "Copy_After");
   Require_Text ("docs/api-reference.md", "Copy_Match_Line");
   Require_Text ("docs/api-reference.md", "Copy_Capture");
   Require_Text ("docs/api-reference.md", "Copy_Named_Capture");
   Require_Text ("docs/api-reference.md", "Named_Capture_Range");
   Require_Text ("docs/api-reference.md", "Find_First_With_Captures");
   Require_Text ("docs/api-reference.md", "Next_With_Captures");
   Require_Text ("docs/api-reference.md", "Next_Captured");
   Require_Text ("docs/api-reference.md", "Next_Line_Captured");
   Require_Text ("docs/api-reference.md", "Start_Token_Stream");
   Require_Text ("docs/api-reference.md", "Feed_Tokens");
   Require_Text ("docs/api-reference.md", "Feed_Tokens_Detail");
   Require_Text ("docs/api-reference.md", "Feed_Tokens_With_Captures");
   Require_Text ("docs/api-reference.md", "Token_Stream_Status");
   Require_Text ("docs/api-reference.md", "Benchmark_Pattern");
   Require_Text ("docs/api-reference.md", "Benchmark_Text");
   Require_Text ("docs/api-reference.md", "Benchmark_Summary");
   Require_Text ("docs/api-reference.md", "Make_Token_Name");
   Require_Text ("docs/api-reference.md", "Copy_Token_Name");
   Require_Text ("docs/api-reference.md", "UUID_Pattern");
   Require_Text ("docs/api-reference.md", "Simple_Email_Pattern");
   Require_Text ("docs/api-reference.md", "Max_Captures");
   Require_Text ("docs/api-reference.md", "Max_Capture_Name_Length");
   Require_Text ("docs/api-reference.md", "Too_Many_Captures");
   Require_Text ("docs/api-reference.md", "Invalid_Capture_Name");
   Require_Text ("docs/api-reference.md", "Duplicate_Capture_Name");
   Require_Text ("docs/api-reference.md", "Find_All_Overlapping");
   Require_Text ("docs/api-reference.md", "Find_All_Overlapping_With_Captures");
   Require_Text ("docs/api-reference.md", "Find_All_Overlapping_With_Captures_From");
   Require_Text ("docs/api-reference.md", "Find_All_With_Captures");
   Require_Text ("docs/api-reference.md", "Find_All_With_Captures_From");
   Require_Text ("docs/api-reference.md", "Capture_Result_Array");
   Require_Text ("docs/api-reference.md", "Find_All_Lines");
   Require_Text ("docs/api-reference.md", "Replace_All_Lines");
   Require_Text ("docs/api-reference.md", "Find_All_Summary");
   Require_Text ("docs/api-reference.md", "Find_All_Summary_Result");
   Require_Text ("docs/api-reference.md", "Find_All_Line_Summary");
   Require_Text ("docs/api-reference.md", "Find_All_Line_Summary_Result");
   Require_Text ("docs/api-reference.md", "Stream_Cursor");
   Require_Text ("docs/api-reference.md", "Feed_With_Captures");
   Require_Text ("docs/api-reference.md", "Stream_Buffer_Full");
   Require_Text ("docs/api-reference.md", "Max_Buffer_Length");
   Require_Text ("docs/api-reference.md", "Dot_Matches_Newline");
   Require_Text ("docs/api-reference.md", "Multiline_Anchors");
   Require_Text ("docs/api-reference.md", "Diagnostic_Image");
   Require_Text ("docs/api-reference.md", "Matches_Entire");
   Require_Text ("docs/api-reference.md", "Status_Image");
   Require_Text ("docs/api-reference.md", "Is_Syntax_Error");
   Require_Text ("docs/api-reference.md", "Is_Unsupported");
   Require_Text ("docs/api-reference.md", "Is_Limit_Error");
   Require_Text ("docs/api-reference.md", "Syntax Scope");
   Require_Text ("docs/api-reference.md", "&&[...]");
   Require_Text ("docs/api-reference.md", "--[...]");
   Require_Text ("docs/api-reference.md", "(?:...)");
   Require_Text ("docs/api-reference.md", "(?<name>...)");
   Require_Text ("docs/api-reference.md", "(?=...)");
   Require_Text ("docs/api-reference.md", "(?!...)");
   Require_Text ("docs/api-reference.md", "(?<=...)");
   Require_Text ("docs/api-reference.md", "(?<!...)");
   Require_Text ("README.md", "(?=cat)");
   Require_Text ("README.md", "(?!cat)");
   Require_Text ("README.md", "(?<=cat)");
   Require_Text ("README.md", "(?<!cat)");
   Require_Text ("README.md", "(?i:cat)");
   Require_Text ("README.md", "(?-i:cat)");
   Require_Text ("README.md", "(?m:^cat)");
   Require_Text ("README.md", "(?s:.)");
   Require_Text ("docs/api-reference.md", "(?i:...)");
   Require_Text ("docs/api-reference.md", "(?-i:...)");
   Require_Text ("docs/api-reference.md", "(?m:...)");
   Require_Text ("docs/api-reference.md", "(?s:...)");
   Require_Text ("README.md", "\1");
   Require_Text ("README.md", "\k<name>");
   Require_Text ("README.md", "*+");
   Require_Text ("README.md", "(?>cat|dog)");
   Require_Text ("docs/api-reference.md", "(?>...)");
   Require_Text ("docs/api-reference.md", "Possessive quantifiers");
   Require_Text ("docs/api-reference.md", "Lazy quantifiers");
   Require_Text ("docs/api-reference.md", "Numbered capture grouping");
   Require_Text ("docs/api-reference.md", "Unsupported_Syntax");
   Require_Text ("README.md", "[[:alpha:]]");

   Require_Text (".gitignore", "/examples/obj/");
   Require_Text (".gitignore", "/examples/bin/");
   Require_Text (".gitignore", "/tests/obj/");
   Require_Text (".gitignore", "/tests/bin/");
   Require_Text (".gitignore", "/check_regexp/obj/");
   Require_Text (".gitignore", "/tools/obj/");
   Require_Text (".gitignore", "*.kate-swp");

   Require_Text ("alire.toml", "[[actions]]");
   Require_Text ("alire.toml", "type = ""test""");
   Require_Text ("alire.toml", "cd tests && alr build && ./bin/tests");
   Require_Text ("alire.toml", "gnat_native = ""=15.2.1""");
   Require_Text ("tests/alire.toml", "gnat_native = ""=15.2.1""");
   Require_Text ("check_regexp/alire.toml", "gnat_native = ""=15.2.1""");

   Require_Text ("tools/check_all.adb", "Project_Tools.Processes");
   Require_Text ("tools/check_all.adb", "Require_Command");
   Require_Text ("tools/check_all.adb", "Require_Clean_Git_Worktree");
   Require_Text ("tools/check_all.adb", "Require_Alire_GNAT_15");
   Require_Text ("tools/check_all.adb", "GNATLS 15.");
   Require_Text ("tools/check_all.adb", "alr exec -- gnatls --version");
   Require_Text ("tools/check_all.adb", "gnatprove");
   Require_Text ("tools/check_all.adb", "--level=4");
   Require_Text ("tools/check_all.adb", "alr test");
   --  tools/ is its own Alire crate now: the project_tools dependency is
   --  declared in its manifest, and Alire writes the with into the generated
   --  config gpr. Assert on the manifest, which is where the truth moved.
   Require_Text ("tools/alire.toml", "project_tools");
   Require_Text ("docs/SPARK.md", "alr exec -- gnatprove -P regexp.gpr --level=4");
   Require_Text ("docs/SPARK.md", "mandatory for release validation");
   Require_Text ("docs/ai-usage.md", "tools/bin/check_all");
   Require_Text ("docs/ai-usage.md", "check_regexp/alire.release.toml");
   Require_Text ("docs/ai-usage.md", "clean Git worktree");
   Require_Text ("docs/ai-usage.md", "Compile_Literal_Set");
   Require_Text ("docs/ai-usage.md", "Compile_Literal_Word_Set");
   Require_Text ("docs/ai-usage.md", "Compile_Literal_Anchored");
   Require_Text ("docs/ai-usage.md", "Compile_Line");
   Require_Text ("docs/ai-usage.md", "Compile_Literal_Line");
   Require_Text ("docs/ai-usage.md", "Supports_Syntax");
   Require_Text ("docs/ai-usage.md", "Syntax_Feature_Image");
   Require_Text ("docs/ai-usage.md", "Supported_Syntax");
   Require_Text ("docs/ai-usage.md", "Supported_Syntax_Detail");
   Require_Text ("docs/ai-usage.md", "Syntax_Support");
   Require_Text ("docs/ai-usage.md", "Append_Class_Literal");
   Require_Text ("docs/ai-usage.md", "Build_Character_Class");
   Require_Text ("docs/ai-usage.md", "Build_Literal_Alternation");
   Require_Text ("docs/ai-usage.md", "Recommended_Strategy");
   Require_Text ("docs/ai-usage.md", "Summary");
   Require_Text ("docs/ai-usage.md", "Fingerprint");
   Require_Text ("docs/ai-usage.md", "Pattern_Fingerprint");
   Require_Text ("docs/ai-usage.md", "Metadata");
   Require_Text ("docs/ai-usage.md", "Pattern_Metadata");
   Require_Text ("docs/ai-usage.md", "Source_Kind");
   Require_Text ("docs/ai-usage.md", "Copy_Source_Pattern");
   Require_Text ("docs/ai-usage.md", "Lint");
   Require_Text ("docs/ai-usage.md", "Compile_Diagnostic");
   Require_Text ("docs/ai-usage.md", "Replacement_Diagnostic");
   Require_Text ("docs/ai-usage.md", "Explain_Nodes");
   Require_Text ("docs/ai-usage.md", "Default_Options");
   Require_Text ("docs/ai-usage.md", "UTF_8_Options");
   Require_Text ("docs/ai-usage.md", "UTF_8_Mode");
   Require_Text ("docs/ai-usage.md", "Validate_UTF_8");
   Require_Text ("docs/ai-usage.md", "UTF_8_Validation_Result");
   Require_Text ("docs/ai-usage.md", "Find_First_Line");
   Require_Text ("docs/ai-usage.md", "Next_With_Captures");
   Require_Text ("docs/ai-usage.md", "Named_Captures");
   Require_Text ("docs/ai-usage.md", "Match_Length");
   Require_Text ("docs/ai-usage.md", "Find_All_Summary");
   Require_Text ("docs/ai-usage.md", "Find_All_Line_Summary");
   Require_Text ("docs/ai-usage.md", "Find_All_With_Captures");
   Require_Text ("docs/ai-usage.md", "Find_All_Overlapping_With_Captures");
   Require_Text ("docs/ai-usage.md", "Find_First_Of");
   Require_Text ("docs/ai-usage.md", "Find_From_Of");
   Require_Text ("docs/ai-usage.md", "Tokenize");
   Require_Text ("docs/ai-usage.md", "Tokenize_With_Kinds");
   Require_Text ("docs/ai-usage.md", "Find_First_Of_With_Captures");
   Require_Text ("docs/ai-usage.md", "Find_From_Of_With_Captures");
   Require_Text ("docs/ai-usage.md", "Tokenize_With_Captures");
   Require_Text ("docs/ai-usage.md", "Find_From_Planned");
   Require_Text ("docs/ai-usage.md", "Find_From_Planned_With_Captures");
   Require_Text ("docs/ai-usage.md", "Feed_With_Captures");
   Require_Text ("docs/ai-usage.md", "Features");
   Require_Text ("docs/ai-usage.md", "Validate_Policy");
   Require_Text ("docs/ai-usage.md", "Validate_Policy_Detail");
   Require_Text ("docs/ai-usage.md", "Policy_Feature");
   Require_Text ("docs/ai-usage.md", "Literal_Search_Policy");
   Require_Text ("docs/ai-usage.md", "Safe_User_Search_Policy");
   Require_Text ("docs/ai-usage.md", "Streaming_Search_Policy");
   Require_Text ("docs/ai-usage.md", "Editor_Replace_Policy");
   Require_Text ("docs/ai-usage.md", "No_Empty_Match_Policy");
   Require_Text ("docs/ai-usage.md", "No_Lookaround_Policy");
   Require_Text ("docs/ai-usage.md", "No_Backreferences_Policy");
   Require_Text ("docs/ai-usage.md", "Copy_Named_Capture");
   Require_Text ("docs/ai-usage.md", "Named_Capture_Range");
   Require_Text ("docs/ai-usage.md", "Find_All_Lines");
   Require_Text ("docs/ai-usage.md", "Replace_All_Lines");
   Require_Text ("docs/ai-usage.md", "Split_Lines");
   Require_Text ("docs/ai-usage.md", "Validate_Replacement_Detail");
   Require_Text ("docs/ai-usage.md", "Replacement_References");
   Require_Text ("docs/ai-usage.md", "Replacement_Summary");
   Require_Text ("docs/ai-usage.md", "Escape_Replacement");
   Require_Text ("docs/ai-usage.md", "Is_Limit_Error");
   Require_Text ("docs/ai-usage.md", "Replace_All_Size");
   Require_Text ("docs/ai-usage.md", "Required_First_Output_Length");
   Require_Text ("docs/ai-usage.md", "Required_All_Output_Length");
   Require_Text ("docs/ai-usage.md", "Replacement_Fits");
   Require_Text ("docs/ai-usage.md", "Plan_Replacement");
   Require_Text ("docs/ai-usage.md", "Plan_Replacement_Detail");
   Require_Text ("docs/ai-usage.md", "Replacement_Output_Map");
   Require_Text ("docs/ai-usage.md", "Replacement_Plan");
   Require_Text ("docs/ai-usage.md", "Next_Captured");
   Require_Text ("docs/ai-usage.md", "Next_Line_Captured");
   Require_Text ("docs/ai-usage.md", "Start_Token_Stream");
   Require_Text ("docs/ai-usage.md", "Feed_Tokens");
   Require_Text ("docs/ai-usage.md", "Feed_Tokens_Detail");
   Require_Text ("docs/ai-usage.md", "Feed_Tokens_With_Captures");
   Require_Text ("docs/ai-usage.md", "Token_Stream_Status");
   Require_Text ("docs/ai-usage.md", "Benchmark_Pattern");
   Require_Text ("docs/ai-usage.md", "Benchmark_Text");
   Require_Text ("docs/ai-usage.md", "Benchmark_Summary");
   Require_Text ("docs/ai-usage.md", "Make_Token_Name");
   Require_Text ("docs/ai-usage.md", "Copy_Token_Name");
   Require_Text ("docs/ai-usage.md", "Format_Compile_Diagnostic");
   Require_Text ("docs/ai-index.json", "release_check");
   Require_Text ("docs/ai-index.json", "staged_manifest_workflow");
   Require_Text ("docs/ai-index.json", "Compile_Literal_Set");
   Require_Text ("docs/ai-index.json", "Compile_Literal_Word_Set");
   Require_Text ("docs/ai-index.json", "Compile_Literal_Whole_Word");
   Require_Text ("docs/ai-index.json", "Compile_Line");
   Require_Text ("docs/ai-index.json", "Compile_Literal_Line");
   Require_Text ("docs/ai-index.json", "Supports_Syntax");
   Require_Text ("docs/ai-index.json", "Syntax_Feature_Image");
   Require_Text ("docs/ai-index.json", "Supported_Syntax");
   Require_Text ("docs/ai-index.json", "Supported_Syntax_Detail");
   Require_Text ("docs/ai-index.json", "Syntax_Support_Array");
   Require_Text ("docs/ai-index.json", "Append_Class_Literal");
   Require_Text ("docs/ai-index.json", "Build_Character_Class");
   Require_Text ("docs/ai-index.json", "Build_Literal_Alternation");
   Require_Text ("docs/ai-index.json", "Recommended_Strategy");
   Require_Text ("docs/ai-index.json", "Summary");
   Require_Text ("docs/ai-index.json", "Fingerprint");
   Require_Text ("docs/ai-index.json", "Pattern_Fingerprint");
   Require_Text ("docs/ai-index.json", "Metadata");
   Require_Text ("docs/ai-index.json", "Pattern_Metadata");
   Require_Text ("docs/ai-index.json", "Source_Kind");
   Require_Text ("docs/ai-index.json", "Copy_Source_Pattern");
   Require_Text ("docs/ai-index.json", "Lint");
   Require_Text ("docs/ai-index.json", "Compile_Diagnostic");
   Require_Text ("docs/ai-index.json", "Replacement_Diagnostic");
   Require_Text ("docs/ai-index.json", "Explain_Nodes");
   Require_Text ("docs/ai-index.json", "Default_Options");
   Require_Text ("docs/ai-index.json", "UTF_8_Options");
   Require_Text ("docs/ai-index.json", "Validate_UTF_8");
   Require_Text ("docs/ai-index.json", "UTF_8_Validation_Result");
   Require_Text ("docs/ai-index.json", "Next_With_Captures");
   Require_Text ("docs/ai-index.json", "Named_Captures");
   Require_Text ("docs/ai-index.json", "Match_Length");
   Require_Text ("docs/ai-index.json", "Validate_Policy");
   Require_Text ("docs/ai-index.json", "Validate_Policy_Detail");
   Require_Text ("docs/ai-index.json", "Pattern_Policy_Diagnostic");
   Require_Text ("docs/ai-index.json", "Policy_Feature");
   Require_Text ("docs/ai-index.json", "Literal_Search_Policy");
   Require_Text ("docs/ai-index.json", "Safe_User_Search_Policy");
   Require_Text ("docs/ai-index.json", "Streaming_Search_Policy");
   Require_Text ("docs/ai-index.json", "Editor_Replace_Policy");
   Require_Text ("docs/ai-index.json", "No_Empty_Match_Policy");
   Require_Text ("docs/ai-index.json", "No_Lookaround_Policy");
   Require_Text ("docs/ai-index.json", "No_Backreferences_Policy");
   Require_Text ("docs/ai-index.json", "Find_All_Lines");
   Require_Text ("docs/ai-index.json", "Replace_All_Lines");
   Require_Text ("docs/ai-index.json", "Split_Lines");
   Require_Text ("docs/ai-index.json", "Find_All_Summary");
   Require_Text ("docs/ai-index.json", "Find_All_Line_Summary");
   Require_Text ("docs/ai-index.json", "Find_All_With_Captures");
   Require_Text ("docs/ai-index.json", "Find_All_Overlapping_With_Captures");
   Require_Text ("docs/ai-index.json", "Find_First_Of");
   Require_Text ("docs/ai-index.json", "Find_From_Of");
   Require_Text ("docs/ai-index.json", "Tokenize");
   Require_Text ("docs/ai-index.json", "Tokenize_With_Kinds");
   Require_Text ("docs/ai-index.json", "Find_First_Of_With_Captures");
   Require_Text ("docs/ai-index.json", "Find_From_Of_With_Captures");
   Require_Text ("docs/ai-index.json", "Tokenize_With_Captures");
   Require_Text ("docs/ai-index.json", "Find_From_Planned");
   Require_Text ("docs/ai-index.json", "Find_From_Planned_With_Captures");
   Require_Text ("docs/ai-index.json", "Feed_With_Captures");
   Require_Text ("docs/ai-index.json", "Replace_All_Count");
   Require_Text ("docs/ai-index.json", "Replace_All_Size");
   Require_Text ("docs/ai-index.json", "Required_First_Output_Length");
   Require_Text ("docs/ai-index.json", "Required_All_Output_Length");
   Require_Text ("docs/ai-index.json", "Replacement_Fits");
   Require_Text ("docs/ai-index.json", "Plan_Replacement");
   Require_Text ("docs/ai-index.json", "Plan_Replacement_Detail");
   Require_Text ("docs/ai-index.json", "Replacement_Output_Map");
   Require_Text ("docs/ai-index.json", "Replacement_Plan");
   Require_Text ("docs/ai-index.json", "Next_Captured");
   Require_Text ("docs/ai-index.json", "Next_Line_Captured");
   Require_Text ("docs/ai-index.json", "Start_Token_Stream");
   Require_Text ("docs/ai-index.json", "Feed_Tokens");
   Require_Text ("docs/ai-index.json", "Feed_Tokens_Detail");
   Require_Text ("docs/ai-index.json", "Feed_Tokens_With_Captures");
   Require_Text ("docs/ai-index.json", "Token_Stream_Status");
   Require_Text ("docs/ai-index.json", "Benchmark_Pattern");
   Require_Text ("docs/ai-index.json", "Benchmark_Text");
   Require_Text ("docs/ai-index.json", "Benchmark_Summary");
   Require_Text ("docs/ai-index.json", "Make_Token_Name");
   Require_Text ("docs/ai-index.json", "Copy_Token_Name");
   Require_Text ("docs/ai-index.json", "Validate_Replacement_Detail");
   Require_Text ("docs/ai-index.json", "Replacement_References");
   Require_Text ("docs/ai-index.json", "Replacement_Summary");
   Require_Text ("docs/ai-index.json", "Escape_Replacement");
   Require_Text ("docs/ai-index.json", "Is_Limit_Error");
   Require_Text ("docs/ai-index.json", "Format_Replacement_Diagnostic");
   Require_Text ("llms.txt", "tools/check_all.adb");
   Require_Text ("llms.txt", "check_regexp/alire.release.toml");
   Require_Text ("llms.txt", "Compile_Literal_Set");
   Require_Text ("llms.txt", "Compile_Literal_Word_Set");
   Require_Text ("llms.txt", "Compile_Literal_Whole_Word");
   Require_Text ("llms.txt", "Compile_Line");
   Require_Text ("llms.txt", "Compile_Literal_Line");
   Require_Text ("llms.txt", "Supports_Syntax");
   Require_Text ("llms.txt", "Syntax_Feature_Image");
   Require_Text ("llms.txt", "Supported_Syntax");
   Require_Text ("llms.txt", "Supported_Syntax_Detail");
   Require_Text ("llms.txt", "Append_Class_Literal");
   Require_Text ("llms.txt", "Build_Character_Class");
   Require_Text ("llms.txt", "Build_Literal_Alternation");
   Require_Text ("llms.txt", "Recommended_Strategy");
   Require_Text ("llms.txt", "Summary");
   Require_Text ("llms.txt", "Fingerprint");
   Require_Text ("llms.txt", "Pattern_Fingerprint");
   Require_Text ("llms.txt", "Metadata");
   Require_Text ("llms.txt", "Pattern_Metadata");
   Require_Text ("llms.txt", "Source_Kind");
   Require_Text ("llms.txt", "Copy_Source_Pattern");
   Require_Text ("llms.txt", "Lint");
   Require_Text ("llms.txt", "Compile_Diagnostic");
   Require_Text ("llms.txt", "Replacement_Diagnostic");
   Require_Text ("llms.txt", "Explain_Nodes");
   Require_Text ("llms.txt", "Default_Options");
   Require_Text ("llms.txt", "UTF_8_Options");
   Require_Text ("llms.txt", "Validate_UTF_8");
   Require_Text ("llms.txt", "UTF_8_Validation_Result");
   Require_Text ("llms.txt", "Find_First_Line");
   Require_Text ("llms.txt", "Next_With_Captures");
   Require_Text ("llms.txt", "Next_Captured");
   Require_Text ("llms.txt", "Next_Line_Captured");
   Require_Text ("llms.txt", "Named_Captures");
   Require_Text ("llms.txt", "Match_Length");
   Require_Text ("llms.txt", "Find_All_Lines");
   Require_Text ("llms.txt", "Replace_All_Lines");
   Require_Text ("llms.txt", "Split_Lines");
   Require_Text ("llms.txt", "Find_All_Summary");
   Require_Text ("llms.txt", "Find_All_Line_Summary");
   Require_Text ("llms.txt", "Find_All_With_Captures");
   Require_Text ("llms.txt", "Find_All_Overlapping_With_Captures");
   Require_Text ("llms.txt", "Find_First_Of");
   Require_Text ("llms.txt", "Find_From_Of");
   Require_Text ("llms.txt", "Tokenize");
   Require_Text ("llms.txt", "Tokenize_With_Kinds");
   Require_Text ("llms.txt", "Find_First_Of_With_Captures");
   Require_Text ("llms.txt", "Find_From_Of_With_Captures");
   Require_Text ("llms.txt", "Tokenize_With_Captures");
   Require_Text ("llms.txt", "Find_From_Planned");
   Require_Text ("llms.txt", "Find_From_Planned_With_Captures");
   Require_Text ("llms.txt", "Start_Token_Stream");
   Require_Text ("llms.txt", "Feed_Tokens");
   Require_Text ("llms.txt", "Feed_Tokens_Detail");
   Require_Text ("llms.txt", "Feed_Tokens_With_Captures");
   Require_Text ("llms.txt", "Token_Stream_Status");
   Require_Text ("llms.txt", "Feed_With_Captures");
   Require_Text ("llms.txt", "Replace_All_Count");
   Require_Text ("llms.txt", "Replace_All_Size");
   Require_Text ("llms.txt", "Required_First_Output_Length");
   Require_Text ("llms.txt", "Required_All_Output_Length");
   Require_Text ("llms.txt", "Replacement_Fits");
   Require_Text ("llms.txt", "Plan_Replacement");
   Require_Text ("llms.txt", "Plan_Replacement_Detail");
   Require_Text ("llms.txt", "Replacement_Output_Map");
   Require_Text ("llms.txt", "Replacement_Plan");
   Require_Text ("llms.txt", "Replacement_References");
   Require_Text ("llms.txt", "Replacement_Summary");
   Require_Text ("llms.txt", "Escape_Replacement");
   Require_Text ("llms.txt", "Safe_User_Search_Policy");
   Require_Text ("llms.txt", "Validate_Policy_Detail");
   Require_Text ("llms.txt", "Pattern_Policy_Diagnostic");
   Require_Text ("llms.txt", "Policy_Feature");
   Require_Text ("llms.txt", "Streaming_Search_Policy");
   Require_Text ("llms.txt", "Editor_Replace_Policy");
   Require_Text ("llms.txt", "No_Empty_Match_Policy");
   Require_Text ("llms.txt", "No_Lookaround_Policy");
   Require_Text ("llms.txt", "No_Backreferences_Policy");
   Require_Text ("llms.txt", "Benchmark_Pattern");
   Require_Text ("llms.txt", "Benchmark_Text");
   Require_Text ("llms.txt", "Benchmark_Summary");
   Require_Text ("llms.txt", "Make_Token_Name");
   Require_Text ("llms.txt", "Copy_Token_Name");
   Require_Text ("llms.txt", "Is_Limit_Error");
   Require_Text ("check_regexp/README.md", "alire.release.toml");
   Require_Text ("check_regexp/README.md", "alire.build.toml");
   Require_Text ("check_regexp/alire.toml", "project_tools");
   Require_Text ("check_regexp/alire.release.toml", "project_tools = ""*""");
   Require_Manifest_Policy;
   Require_Check_Regexp_Staging_Workflow;

   Require_Documented_Example ("examples/src/basic_search.adb");
   Require_Documented_Example ("examples/src/case_sensitivity.adb");
   Require_Documented_Example ("examples/src/whole_word.adb");
   Require_Documented_Example ("examples/src/find_from_offsets.adb");
   Require_Documented_Example ("examples/src/find_all_matches.adb");
   Require_Documented_Example ("examples/src/matches_entire.adb");
   Require_Documented_Example ("examples/src/character_classes.adb");
   Require_Documented_Example ("examples/src/preset_patterns.adb");
   Require_Documented_Example ("examples/src/lookaround_options.adb");
   Require_Documented_Example ("examples/src/search_workflow.adb");
   Require_Documented_Example ("examples/src/advanced_search_planning.adb");
   Require_Documented_Example ("examples/src/compile_errors.adb");
   Require_Documented_Example ("examples/src/step_limit.adb");
   Require_Examples_Inventory;
   Require_Example_Public_API_Only;
   Require_Example_Failure_Handling;
   Require_Example_Outputs;
   Require_Source_Policy;
   Require_AUnit_Inventory;
   Require_Release_Tree_Clean;

   Put_Line ("regexp docs check passed.");
exception
   when Program_Error =>
      null;
end Check_Regexp;
