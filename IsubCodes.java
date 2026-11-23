import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Prints the transaction codes the module needs, read by reflection from the running ROM,
 * with each method's parameter types for checking. Read-only.
 * Run as root:  CLASSPATH=isubcodes.dex app_process / IsubCodes
 * Output: "<method>=<code> sig=<params> ok|MISMATCH"
 */
public class IsubCodes {
    static final String[][] METHODS = {
        // interface, method, expected parameter types
        {"com.android.internal.telephony.ISub", "setDefaultDataSubId", "int"},
        {"com.android.internal.telephony.ISub", "setUiccApplicationsEnabled", "boolean,int"},
        {"com.android.internal.telephony.ISub", "setDefaultVoiceSubId", "int"},
        {"com.android.internal.telephony.ISub", "setDefaultSmsSubId", "int"},
        {"com.android.internal.telephony.ITelephony", "setDataEnabledForReason", "int,int,boolean,java.lang.String"},
        {"com.android.internal.telephony.ITelephony", "isDataEnabledForReason", "int,int"},
    };

    public static void main(String[] args) throws Exception {
        for (String[] m : METHODS) {
            String ifaceName = m[0], name = m[1], expected = m[2];
            int code = -1;
            String sig = "missing";
            try {
                Class<?> iface = Class.forName(ifaceName);
                Class<?> stub = Class.forName(ifaceName + "$Stub");
                try {
                    Field f = stub.getDeclaredField("TRANSACTION_" + name);
                    f.setAccessible(true);
                    code = f.getInt(null);
                } catch (NoSuchFieldException e) { /* not in this ROM */ }
                for (Method x : iface.getMethods()) {
                    if (!x.getName().equals(name)) continue;
                    StringBuilder sb = new StringBuilder();
                    for (Class<?> p : x.getParameterTypes()) { if (sb.length() > 0) sb.append(','); sb.append(p.getName()); }
                    sig = sb.toString();
                    break;
                }
            } catch (ClassNotFoundException e) { /* interface missing */ }
            System.out.println(name + "=" + code + " sig=" + sig + (sig.equals(expected) ? " ok" : " MISMATCH"));
        }
    }
}
