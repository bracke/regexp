with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Tree_Checks;

procedure Check_All is
   use Ada.Strings.Unbounded;

   Root   : constant String := Ada.Directories.Full_Name (".");
   Alr    : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Checks : constant Project_Tools.Release_Checks.Checker :=
     Project_Tools.Release_Checks.Create (Root);

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Release_Checks.Run;

   procedure Require_Alire_GNAT_15 is
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          (Label   => "GNAT 15 version check",
           Dir     => Root,
           Program => Alr,
           Args    =>
             [1 => new String'("exec"),
              2 => new String'("--"),
              3 => new String'("gnatls"),
              4 => new String'("--version")],
           Output  => Output,
           Quiet   => True);

      if Status /= 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "could not run `alr exec -- gnatls --version`");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      elsif Ada.Strings.Fixed.Index (To_String (Output), "GNATLS 15.") = 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "wrong Ada compiler: regexp validation must use Alire GNAT 15; got: "
            & To_String (Output));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Alire_GNAT_15;

begin
   Project_Tools.Processes.Require_Command
     ("alr", "alr executable not found on PATH");
   Require_Alire_GNAT_15;

   Project_Tools.Release_Checks.Require_File (Checks, "regexp.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tests/tests.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "examples/examples.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/tools.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "check_regexp/check_regexp.gpr");

   Run ("alr build", Root, Alr, [1 => new String'("build")]);
   Run
     ("regexp.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("regexp.gpr")]);
   Run
     ("tests.gpr",
      Root & "/tests",
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tests.gpr")]);
   Run ("AUnit tests", Root & "/tests", "./bin/tests", []);
   Run ("alr test", Root, Alr, [1 => new String'("test")]);
   Run
     ("examples.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("examples/examples.gpr")]);
   Run
     ("tools.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tools/tools.gpr")]);
   Run ("check_regexp build", Root & "/check_regexp", Alr, [1 => new String'("build")]);
   Run ("check_regexp", Root & "/check_regexp", "./bin/check_regexp", []);

   Run
     ("SPARK proof",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("regexp.gpr"), new String'("--level=4")]);

   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tests/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/examples/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tools/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/check_regexp/obj");

   Project_Tools.Release_Checks.Require_Clean_Git_Worktree ("regexp", Root);

   Ada.Text_IO.Put_Line ("regexp release checklist passed");
exception
   when Program_Error =>
      Ada.Text_IO.Put_Line ("regexp release checklist failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Check_All;
