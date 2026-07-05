with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Ada_Source;
with Project_Tools.Alire_Manifests;
with Project_Tools.AUnit_Checks;
with Project_Tools.Files;
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

      Stage  : constant String := "/tmp/regexp-release-tree-check";
      Errors : Natural := 0;

      procedure Report (Path : String; Message : String) is
      begin
         Put_Line (Standard_Error, "error: " & Message & ": " & Path);
         Errors := Errors + 1;
      end Report;

      function Has_Suffix (Text : String; Suffix : String) return Boolean is
        (Text'Length >= Suffix'Length
         and then Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix);

      procedure Check_Tree (Dir : String) is
         Search    : Ada.Directories.Search_Type;
         Dir_Entry : Ada.Directories.Directory_Entry_Type;
      begin
         Ada.Directories.Start_Search (Search, Dir, "");
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Dir_Entry);

            declare
               Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
               Path : constant String := Ada.Directories.Full_Name (Dir_Entry);
            begin
               if Name = "." or else Name = ".." then
                  null;
               elsif Name in "alire" | "bin" | "config" | "lib" | "obj" then
                  Report (Path, "generated directory reached staged release tree");
               elsif Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Directory then
                  Check_Tree (Path);
               elsif Has_Suffix (Name, ".ali")
                 or else Has_Suffix (Name, ".o")
                 or else Has_Suffix (Name, ".bexch")
                 or else Has_Suffix (Name, ".stdout")
                 or else Has_Suffix (Name, ".stderr")
                 or else Has_Suffix (Name, ".cswi")
               then
                  Report (Path, "generated build file reached staged release tree");
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      exception
         when others =>
            Ada.Directories.End_Search (Search);
            raise;
      end Check_Tree;
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

      Check_Tree (Stage);
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
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False);
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
   end Require_Manifest_Policy;

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
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/tools/check_all.adb"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/tools/tools.gpr")],
      "required regexp release file missing",
      Quiet => False);

   Require_Text ("LICENSE", "MIT License");
   Require_Text ("LICENSE", "Apache License");
   Require_Text ("LICENSE", "LLVM Exceptions");
   Require_Text ("alire.toml", "MIT OR Apache-2.0 WITH LLVM-exception");

   Require_Text ("README.md", "LICENSE");
   Require_Text ("README.md", "gnatprove -P regexp.gpr --level=4");
   Require_Text ("README.md", "docs/SPARK.md");
   Require_Text ("README.md", "alr test");
   Require_Text ("README.md", "docs/api-reference.md");
   Require_Text ("README.md", "docs/ai-usage.md");
   Require_Text ("README.md", "llms.txt");
   Require_Text ("README.md", "gprbuild -P regexp.gpr");
   Require_Text ("README.md", "tests/bin/tests");
   Require_Text ("README.md", "tools/bin/check_all");
   Require_Text ("README.md", "check_regexp");

   Require_Text ("docs/api-reference.md", "package Regexp is");
   Require_Text ("docs/api-reference.md", "Compile_Result");
   Require_Text ("docs/api-reference.md", "Match_Options");
   Require_Text ("docs/api-reference.md", "Find_First");
   Require_Text ("docs/api-reference.md", "Find_From");
   Require_Text ("docs/api-reference.md", "Matches_Entire");
   Require_Text ("docs/api-reference.md", "Status_Image");
   Require_Text ("docs/api-reference.md", "Syntax Scope");
   Require_Text ("docs/api-reference.md", "Unsupported_Syntax");

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
   Require_Text ("tools/check_all.adb", "gnatprove executable not found on PATH");
   Require_Text ("tools/check_all.adb", "gnatprove");
   Require_Text ("tools/check_all.adb", "--level=4");
   Require_Text ("tools/check_all.adb", "alr test");
   Require_Text ("tools/tools.gpr", "project_tools.gpr");
   Require_Text ("docs/SPARK.md", "gnatprove -P regexp.gpr --level=4");
   Require_Text ("docs/SPARK.md", "mandatory for release validation");
   Require_Text ("check_regexp/alire.toml", "project_tools");
   Require_Manifest_Policy;

   Require_Documented_Example ("examples/src/basic_search.adb");
   Require_Documented_Example ("examples/src/case_sensitivity.adb");
   Require_Documented_Example ("examples/src/whole_word.adb");
   Require_Documented_Example ("examples/src/find_from_offsets.adb");
   Require_Documented_Example ("examples/src/matches_entire.adb");
   Require_Documented_Example ("examples/src/character_classes.adb");
   Require_Documented_Example ("examples/src/compile_errors.adb");
   Require_Documented_Example ("examples/src/step_limit.adb");
   Require_Examples_Inventory;
   Require_Example_Public_API_Only;
   Require_Source_Policy;
   Require_AUnit_Inventory;
   Require_Release_Tree_Clean;

   Put_Line ("regexp docs check passed.");
exception
   when Program_Error =>
      null;
end Check_Regexp;
