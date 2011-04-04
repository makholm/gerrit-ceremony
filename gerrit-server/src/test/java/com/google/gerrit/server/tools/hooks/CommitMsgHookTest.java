import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import static org.junit.Assume.assumeTrue;

import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TestName;
  @Rule public TestName test = new TestName();
  private void skipIfWin32Platform() {
    if (HostPlatform.isWin32()) {
      System.err.println(" - Skipping " + test.getMethodName() + " on this system");
      assumeTrue(false);
    }
  @Before
  public void setUp() throws Exception {
    skipIfWin32Platform();
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test
  @Test