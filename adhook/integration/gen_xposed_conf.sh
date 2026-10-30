# Apply this patch to the FX KernelSU source file scripts/gen_xposed_conf.sh.
# Target branch: fx-v1.0.0-unified-hook-integration
@@ -238,7 +238,7 @@
           if (n < 2) next
           pkg=a[1]; splash=feed=overlay=member=privacy=exif=clipboard=0
           sensor_accel=sensor_gyro=sensor_light=sensor_magnet=sensor_pressure=sensor_prox=sensor_rate_limit=0; wifi_scan=0; notification_listen=0; notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
-          rules=""; valid=1
+          rules=""; dev_enabled=0; dev_rule_count=0; dev_rules=""; dev_seen_ids=""; valid=1
           if (pkg !~ /^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z0-9_]+)+$/) next
           for (i=2;i<=n;i++) {
             eq=index(a[i], "=")
@@ -259,6 +259,24 @@
               if (!valid) break
               rules=val; continue
             }
+            if (key == "dev_hook_enabled") {
+              if (val != "0" && val != "1") { valid=0; break }
+              dev_enabled=val; continue
+            }
+            if (key ~ /^dev_rule_[0-9][0-9]?$/) {
+              if (dev_rule_count >= 64) { valid=0; break }
+              nfields=split(val, dev_parts, "|")
+              if (nfields != 4 || dev_parts[1] !~ /^[A-Za-z][A-Za-z0-9_-]{0,31}$/ ||
+                  dev_parts[2] !~ /^L[A-Za-z_$][A-Za-z0-9_$/]*;->[A-Za-z_$<>][A-Za-z0-9_$<>]*\(.*\).+$/ ||
+                  (dev_parts[3] != "OBSERVE" && dev_parts[3] != "DISABLED" && dev_parts[3] != "RETURN_TRUE" && dev_parts[3] != "RETURN_FALSE") ||
+                  dev_parts[4] !~ /^-?[0-9]+$/ || dev_parts[4] < -1000 || dev_parts[4] > 1000) { valid=0; break }
+              if (index(dev_seen_ids, "|" dev_parts[1] "|") > 0) valid=0
+              if (!valid) break
+              dev_seen_ids=dev_seen_ids "|" dev_parts[1] "|"
+              dev_rule_count++
+              dev_rules=dev_rules sprintf(",dev_rule_%d=%s", dev_rule_count, val)
+              continue
+            }
             if (val != "0" && val != "1") { valid=0; break }
             if (key == "splash") splash=val
             else if (key == "feed") feed=val
@@ -291,9 +309,11 @@
                   (ruleCategory == "overlay" && overlay != 1)) { valid=0; break }
             }
           }
-          if (!valid || (clipboard && clipboard_isolate) || (!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence) && rules == "")) next
+          if (!valid || (clipboard && clipboard_isolate) || (!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence+dev_enabled+dev_rule_count) && rules == "")) next
           printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence
           if (rules != "") printf ",rules=%s", rules
+          printf ",dev_hook_enabled=%s", dev_enabled
+          if (dev_rules != "") printf "%s", dev_rules
           printf "\n"
         }
       ' "$XDIR/settings.conf"
