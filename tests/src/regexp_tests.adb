with Regexp_Tests.Api_Tests;
with Regexp_Tests.Compile_Tests;
with Regexp_Tests.Entry_Tests;
with Regexp_Tests.Focused_Tests;
with Regexp_Tests.Limit_Tests;
with Regexp_Tests.Match_Tests;
with AUnit.Test_Cases;

package body Regexp_Tests is
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Ret : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Api_Tests.Test_Case));
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Compile_Tests.Test_Case));
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Match_Tests.Test_Case));
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Entry_Tests.Test_Case));
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Limit_Tests.Test_Case));
      Ret.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Regexp_Tests.Focused_Tests.Test_Case));
      return Ret;
   end Suite;
end Regexp_Tests;
