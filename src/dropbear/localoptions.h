#ifndef DROPBEAR_LOCALOPTIONS_H
#define DROPBEAR_LOCALOPTIONS_H

#define RSA_PRIV_FILENAME "/home/yi-hack/config/dropbear/dropbear_rsa_host_key"
#define ECDSA_PRIV_FILENAME "/home/yi-hack/config/dropbear/dropbear_ecdsa_host_key"
#define ED25519_PRIV_FILENAME "/home/yi-hack/config/dropbear/dropbear_ed25519_host_key"

#define DROPBEAR_PATH_SSH_PROGRAM "/home/yi-hack/base/bin/dbclient"

#define DEFAULT_PATH "/usr/bin:/usr/sbin:/bin:/sbin:/home/yi-hack/base/bin:/home/yi-hack/extra/bin"

/* dropbear gives root sessions DEFAULT_ROOT_PATH, NOT DEFAULT_PATH (svr-chansession.c).
 * The camera is root-only, so without base/bin + extra/bin here, non-interactive root
 * sessions (scp sink `scp -t`, `ssh cam <cmd>`) cannot find v6 binaries -> scp -O fails.
 * Login shells fix PATH via /etc/profile, but scp/remote-exec do NOT source it. */
#define DEFAULT_ROOT_PATH "/usr/sbin:/usr/bin:/sbin:/bin:/home/yi-hack/base/bin:/home/yi-hack/extra/bin"

/* sftp-server lives in the payload (extra/, on SD/CIFS), not in flash base.
 * SFTPSERVER_PATH is consulted at RUNTIME: dropbear execs it per sftp session, so sftp
 * starts working automatically once extra is mounted and the binary is present - no
 * dropbear restart needed. In minimal boot (no payload) the path is absent -> sftp
 * unavailable -> use `scp -O` (legacy SCP protocol), always served by the scp applet
 * compiled into dropbearmulti in base/bin. TODO (see CAMERA_FIRMWARE_DESIGN §9): build
 * an sftp-server for this platform and ship it at extra/bin/sftp-server. */
#define SFTPSERVER_PATH "/home/yi-hack/extra/bin/sftp-server"

#endif /* DROPBEAR_LOCALOPTIONS_H */
