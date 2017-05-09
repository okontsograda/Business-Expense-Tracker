<?php

session_start();

require_once 'include/navbar.php';

error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);


if ( !isset ( $_SESSION['user'] ) ) {
	header ( 'location: index.php' );
}

$dbh = new DB();


if ( $_GET ) {
	$case_id = $_GET['id'];
	$query = "SELECT * FROM `case_summary` where `case_id` = '$case_id'";

	$case_detail = $dbh->connect_db()->query( $query )->fetchAll();

}

?>

<!DOCTYPE html>
<html>
<head>
	<title>SC </title>

	<!-- Custom Stylesheet -->
	<link rel="stylesheet" type="text/css" href="include/case_summary.css">
	<!-- Navbar Include - Load navbar and content permissions -->

</head>

<body>


<div class="container-fluid">
	<div class="row">
		<div class="col-md-6 col-lg-6">
			<div class="panel panel-default">
				<div class="panel-heading">
					<h6 class="panel-title">Details</h6>
				</div>
				<div class="panel-body">
					<div class="container">
						<div class="row">
							<div class="col-md-1">
								<label class="case-detail-label">ST #</label>
								<div class="case-detail">02</div>
							</div>
							<div class="col-md-5">
								<label class="case-detail-label">Subject</label>
								<div class="case-detail text-left">Re-assign to new engineer for further investigation to look into</div>
							</div>
						</div>
						<div class="row">
							<div class="col-md-2">
								<label class="case-detail-label">Assigned</label>
								<div class="case-detail">okontsograda</div>
							</div>
							<div class="col-md-2">
								<label class="case-detail-label">Requested</label>
								<div class="case-detail">dbrovka</div>
							</div>
							<div class="col-md-1">
								<label class="case-detail-label">Status</label>
								<div class="case-detail">Pending Intel</div>
							</div>
							<div class="col-md-1">
								<label class="case-detail-label">Priority</label>
								<h5 class="text-left"><span class="label label-danger">Critical</span></h5>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
		<div class="col-md-6 col-lg-6">
			<div class="panel panel-default">
				<div class="panel-heading">
					<h6 class="panel-title">Summary</h6>
				</div>
				<div class="panel-body">
					<label class="case-detail-label">Summary</label>
					<div class="case-detail">This is the case summary that will describe the issue going on with the user and the stuff they're experiencing.</div>
				</div>
			</div>
		</div>
	</div>
</div>
<div class="container-fluid">
	<div class="row">
		
		<div class="col-md-8 col-lg-8">
			<div class="panel panel-default">
				<div class="panel-heading">
					<h6 class="panel-title">Updates</h6>
				</div>
				<div class="panel-body">
					<div class="container-fluid">
						<div class="row">
							<div>This is the form for new comments</div>
						</div>
					</div>
				</div>
				<div class="panel-body">
					<div class="container-fluid">
						<?php 

						if ( isset ( $case_detail ) && !empty ( $case_detail ) ) {
							foreach ( $case_detail as $detail ) {
								print '
									<div class="row">
										<div class="panel">
											<div class="panel-body panel-updates">
												<div class="container-fluid">
													<div class="row">
														<div class="pull-left"><h5 class="case-title">' . $detail['user'] . '</h5></div>
														<div class="case-time pull-right">' . $detail['datetime'] . '</div>
													</div>
													<div class="row">
														<div class="panel-body panel-comment">' . $detail['comment'] . '</div>
													</div>	
												</div>	
											</div>
										</div>
									</div>';
							}
						}

						?>
					</div>
				</div>
			</div>
		</div>
	</div>
</div>


</body>

</html>