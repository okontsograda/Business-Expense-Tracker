<?php

session_start();

// Require the class file to be loaded
require_once 'include/util_class.php';

// DB connection handle
$dbh = new DB();

// Logger handle
$logger = new logger();

// Check if a session is set, if not -> redirect to login
if ( ! isset ( $_SESSION['user'] ) ) {
	$logger->log_message ( "[redirect] Access attempted to reports.php without login -> redirecting to login", 2, "kbrothers" );
  header ( "location: index.php" );
}

// Assign session identifyer to a user variable
$user = $_SESSION['user'];

// Set the timezone to New York
date_default_timezone_set('America/New_York');


// Create case logic


	if ( isset ( $_POST['create-case'] ) )  {
		// Assign input values to variables
		$case_subject 		= htmlspecialchars( $_POST['subject'] );
		$case_priority		= htmlspecialchars( $_POST['priority'] );
		$case_assigned		= htmlspecialchars( $_POST['assigned'] );
		$case_requested		= htmlspecialchars( $_POST['requested'] );
		$case_status			= htmlspecialchars( $_POST['status'] );
		$case_description = htmlspecialchars( $_POST['description'] );

		$insert_query = "INSERT INTO `case_list` SET `subject` = :case_subject, `description` = :case_description, `priority` = :case_priority, `status` = :case_status, `assigned` = :case_assigned, `requested` = :case_requested, `created` = now(), `updated` = now()";

		$sql = $dbh->connect_db()->prepare( $insert_query );
		$sql->bindParam(':case_subject', $case_subject );
		$sql->bindParam(':case_description', $case_description );
		$sql->bindParam(':case_priority', $case_priority );
		$sql->bindParam(':case_status', $case_status );
		$sql->bindParam(':case_assigned', $case_assigned );
		$sql->bindParam(':case_requested', $case_requested );

		if ( $sql->execute() ) {
			header ( 'location: cases.php' );
		} else {
			print "Unable to insert new case<br/>";
		}

	}


// CASE LIST DETAIL DATA

$case_count_query = "SELECT * from `case_list`";
$case_list = $dbh->connect_db()->query( $case_count_query )->fetchAll();

$open_cases_query = "SELECT * FROM `case_list`";
$open_cases_count = $dbh->connect_db()->query( $open_cases_query)->rowCount();

// Pull data for Assigned / Requested Drop Down

$user_query = "SELECT * FROM `users`";
$users = $dbh->connect_db()->query( $user_query )->fetchAll();

?>

<!DOCTYPE html>
<html>
<head>
	<title>Cases</title>

  <!-- Navigation Bar Template -->
  <?php require_once'include/navbar.php'; ?>

  <!-- VIEWPORT FOR MOBILE DEVICES -->
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>

  <link rel="stylesheet" href="include/cases.css">


</head>

<body>

<div class="container-fluid">
	<div class="row">
		<div class="col-xs-12 col-sm-12 col-md-3 col-lg-3">
			<div class="panel-group">
				<div class="panel panel-default">
					<div class="panel-heading" data-toggle="collapse" data-target="#nav-list">
						<div class="panel-title">Case Detail</div>
					</div>
					<div id="nav-list" class="panel-body nav-panel in">
						<ul class="list-group nav-list">
							<li class="list-group-item"><span class="badge"><?php print $open_cases_count;?></span>Open</li>
							<li class="list-group-item"><span class="badge">0</span> Deleted</li>
							<li class="list-group-item"><span class="badge">0</span> Working</li>
						</ul>
					</div>
				</div>
			</div>
		</div>
		<div class="col-xs-12 col-sm-12 col-md-9 col-lg-9">
			<div class="panel panel-default">
				<div class="panel-heading" data-toggle="collapse" data-target="#case-list">
					<div class="panel-title">Case Management<a href="#"><span class="glyphicon glyphicon-plus pull-right" data-toggle="modal" data-target="#new-case"></span></a></div>
				</div>
				<!-- NEW CASE MODAL -->
				<div class="modal fade" id="new-case" role="dialog" aria-labelledby="new-case" aria-hidden="true">
					<div class="modal-dialog modal-lg" role="document">
						<div class="modal-content">
							<div class="modal-header">
								<h5 class="modal-title" id="new-case">Create a new case</h5>
								<button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
							</div>
							<div class="modal-body">
								<form action="cases.php" method="post">
									<div class="container-fluid">
										<div class="row">
											<div class="col-md-8 col-lg-8">
													<div class="form-group">
														<input type="text" class="form-control" name="subject" placeholder="Subject">
													</div>
											</div>
											<div class="col-md-4 col-lg-4">
												<div class="form-group">
													<select class="form-control" name="priority">
														<option disabled selected>Priority</option>
														<option>High</option>
														<option>Medium</option>
														<option>Low</option>
													</select>
												</div>
											</div>
										</div>
										<div class="row">
											<div class="col-md-4 col-lg-4">
												<div class="form-group">
													<select class="form-control" name="assigned">
														<option disabled selected="">Assign to</option>
														<?php
															if ( isset ( $users ) && !empty ($users ) ) {
																foreach ( $users as $usr ) {
																	print '<option>' . $usr['username'] . '</option>';
																}
															}
														?>
													</select>
												</div>
											</div>
											<div class="col-md-4 col-lg-4">
												<div class="form-group">
													<select class="form-control" name="requested">
														<option disbaled selected>Requested by</option>
														<?php
															if ( isset ( $users ) && !empty ( $users ) ) {
																foreach ( $users as $usr ) {
																	print '<option>' . $usr['username'] . '</option>';
																}
															}
														?>
													</select>
												</div>
											</div>
											<div class="col-md-4 col-lg-4">
												<div class="form-group">
													<select class="form-control" name="status">
														<option disabled selected>Status</option>
														<option>High</option>
														<option>Medium</option>
														<option>Low</option>
													</select>
												</div>
											</div>
										</div>
										<div class="row">
											<div class="col-md-6 col-lg-6">
												<div class="form-group">
													<label for="description">Description</label>
													<textarea class="form-control" name="description" rows="4"></textarea>
												</div>
											</div>
										</div>
									<button type="submit" name="create-case" class="btn btn-primary pull-right">Create Case</button>
									</div>
								</form>
							</div>
						</div>
					</div>
				</div>
				<div id="case-list" class="panel-body case-panel in">
					<table class="table case-table">
            <thead>
            	<tr>
            		<td class="col-md-6 col-lg-6 text-left">Subject</td>
            		<td class="col-md-1 col-lg-1 text-center">Priority</td>
            		<td class="col-md-1 col-lg-1 text-center">Status</td>
            		<td class="col-md-1 col-lg-1 text-center">Assigned</td>
            		<td class="col-md-1 col-lg-1 text-center">Requested</td>
            		<td class="col-md-1 col-lg-1 text-center">Created</td>
            		<td class="col-md-1 col-lg-1 text-center">Updated</td>
            	</tr>
            </thead>
            <?php
            	foreach ( $case_list as $case_detail ) {
            		print '	<tbody>
            							<tr>
            								<td>
            									<div class="media">
            										<div class="media-body">
            											<a href="case_summary.php?id=' . $case_detail['id'] . '" class="case-subject">' . $case_detail[ 'subject' ] .'</a>
            											<p class="case-detail">' . $case_detail[ 'description' ] . '</p>
            										</div>
            									</div>
            								</td>
            								<td class="text-center badge-font"><span class="label label-danger">' . $case_detail[ 'priority' ] . '</span></td>
            								<td class="text-center badge-font"><span class="label label-warning">' . $case_detail[ 'status'] . '</span></td>
            								<td class="text-center case-font">' . $case_detail[ 'assigned' ] . '</td>
            								<td class="text-center case-font">' . $case_detail[ 'requested' ] . '</td>
            								<td class="text-center case-font">' . date ( 'm/d/y', strtotime ( $case_detail[ 'created' ] ) ) . '</td>
            								<td class="text-center case-font">' . date ( 'm/d/y', strtotime ( $case_detail[ 'updated' ] ) ) . '</td>
            							</tr>
            						</tbody>';
								}
            ?>
					</table>
				</div>
			</div>
		</div>
	</div>
</div>

</body>
</html>
