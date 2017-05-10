<?php

  class DB {

    public function dbConnect( $db_name ) {
      $host       = 'localhost';
      $user       = 'root';
      $password   = 'Ol3g@123';


      try {
        $db = new PDO ( "mysql:host=$host;
                         port=8889;
                         dbname=$db_name;
                         password=$pass" );
      } catch ( Exception $e ) {
        return $e->getMessage();
      }
      return $db;
    }

  }

?>
