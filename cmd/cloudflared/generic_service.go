//go:build !windows && !darwin && !linux

package main

import (
	"fmt"
	"os"

	cli "github.com/urfave/cli/v2"

	"github.com/cloudflare/cloudflared/cmd/cloudflared/cliutil"
)

// OS-specific function for token file creation.
//
// common_service.go (built on every platform) references createTokenFile
// unconditionally. Upstream defines it in the linux/darwin/windows service
// files but not in the generic build, so BSD targets (freebsd/netbsd/openbsd)
// fail with "undefined: createTokenFile". createTokenFileUnix is declared in
// common_service.go, so alias it here exactly as macOS and Linux do.
var createTokenFile = createTokenFileUnix

func runApp(app *cli.App, graceShutdownC chan struct{}) {
	app.Commands = append(app.Commands, &cli.Command{
		Name:  "service",
		Usage: "Manages the cloudflared system service (not supported on this operating system)",
		Subcommands: []*cli.Command{
			{
				Name:   "install",
				Usage:  "Install cloudflared as a system service (not supported on this operating system)",
				Action: cliutil.ConfiguredAction(installGenericService),
			},
			{
				Name:   "uninstall",
				Usage:  "Uninstall the cloudflared service (not supported on this operating system)",
				Action: cliutil.ConfiguredAction(uninstallGenericService),
			},
		},
	})
	app.Run(os.Args)
}

func installGenericService(c *cli.Context) error {
	return fmt.Errorf("service installation is not supported on this operating system")
}

func uninstallGenericService(c *cli.Context) error {
	return fmt.Errorf("service uninstallation is not supported on this operating system")
}