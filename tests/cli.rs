use std::process::{Command, Output};

fn cli(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_opentargetcalls"))
        .args(arguments)
        .output()
        .expect("opentargetcalls must execute")
}

#[test]
fn version_reports_the_package_identity() {
    let output = cli(&["--version"]);
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("opentargetcalls {}\n", env!("CARGO_PKG_VERSION"))
    );
}

#[test]
fn help_describes_the_executable_and_assurance_boundary() {
    let output = cli(&["--help"]);
    assert!(output.status.success());
    let help = String::from_utf8(output.stdout).unwrap();
    assert!(help.starts_with("OpenTargetCalls: vendor-independent targeted calling"));
    assert!(help.contains("opentargetcalls targets"));
    assert!(help.contains("verify checks metadata consistency"));
}

#[test]
fn model_metadata_names_the_lean_namespace() {
    let output = cli(&["proof-contract"]);
    assert!(output.status.success());
    let metadata = String::from_utf8(output.stdout).unwrap();
    assert!(metadata
        .lines()
        .any(|line| line == "proof_contract=OpenTargetCalls.Certificate.V2"));
    assert!(metadata
        .lines()
        .any(|line| line == "lean_selection_theorem=OpenTargetCalls.verifySelection_sound"));
}

#[test]
fn command_errors_identify_the_executable() {
    let output = cli(&["unknown-subcommand"]);
    assert_eq!(output.status.code(), Some(2));
    let error = String::from_utf8(output.stderr).unwrap();
    assert!(error.starts_with("opentargetcalls: unknown command"));
    assert!(error.contains("run opentargetcalls help"));
}
